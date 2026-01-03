import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';
import '../providers/user_data_provider.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem video;
  final Episode episode;
  final List<Episode> episodes;

  const PlayerScreen({
    super.key,
    required this.video,
    required this.episode,
    required this.episodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ApiService _api = ApiService();
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLandscape = false; // true=横屏全屏, false=竖屏全屏
  bool _isBuffering = false;
  double _playbackSpeed = 1.0;
  int _currentEpisodeIndex = 0;
  String? _errorMessage;
  int _savedPosition = 0; // 保存的播放进度
  
  // 网速计算
  String _statusText = '';
  Timer? _statusTimer;
  int _lastBufferedMs = 0;
  DateTime? _lastBufferTime;
  int _loadingSeconds = 0;

  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _currentEpisodeIndex = widget.episodes.indexOf(widget.episode);
    // 获取保存的播放进度
    _getSavedPosition();
    _loadVideo(widget.episode);
  }

  void _getSavedPosition() {
    final history = context.read<UserDataProvider>().history;
    final historyItem = history.firstWhere(
      (h) => h.video.detailUrl == widget.video.detailUrl && 
             h.episodeName == widget.episodes[_currentEpisodeIndex].name,
      orElse: () => HistoryItem(
        video: widget.video,
        episodeName: '',
        position: 0,
        watchedAt: DateTime.now(),
      ),
    );
    _savedPosition = historyItem.position;
  }

  Future<void> _loadVideo(Episode episode, {int retryCount = 0}) async {
    const maxRetries = 3;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusText = retryCount > 0 ? '重试中 ($retryCount/$maxRetries)...' : '获取播放地址...';
      _loadingSeconds = 0;
    });
    
    _startStatusTimer();

    try {
      final url = await _api.getPlayUrl(episode.link);
      if (url == null) {
        // 自动重试
        if (retryCount < maxRetries) {
          setState(() => _statusText = '获取失败，${retryCount + 1}秒后重试...');
          await Future.delayed(Duration(seconds: retryCount + 1));
          return _loadVideo(episode, retryCount: retryCount + 1);
        }
        setState(() {
          _errorMessage = '无法获取播放地址';
          _isLoading = false;
        });
        _stopStatusTimer();
        return;
      }

      setState(() => _statusText = '连接服务器...');

      _controller?.dispose();
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      
      setState(() => _statusText = '加载视频...');
      
      await _controller!.initialize();
      _controller!.setPlaybackSpeed(_playbackSpeed);
      
      // 恢复播放进度
      if (_savedPosition > 5) {
        await _controller!.seekTo(Duration(seconds: _savedPosition - 3)); // 回退3秒
      }
      _savedPosition = 0; // 重置，避免切集时重复跳转
      
      _controller!.play();
      _controller!.addListener(_onVideoUpdate);
      
      _lastBufferedMs = 0;
      _lastBufferTime = DateTime.now();

      setState(() {
        _isLoading = false;
        _statusText = '';
      });
      _stopStatusTimer();
    } catch (e) {
      // 自动重试
      if (retryCount < maxRetries) {
        setState(() => _statusText = '加载失败，${retryCount + 1}秒后重试...');
        await Future.delayed(Duration(seconds: retryCount + 1));
        return _loadVideo(episode, retryCount: retryCount + 1);
      }
      setState(() {
        _errorMessage = '播放失败，请点击重试';
        _isLoading = false;
      });
      _stopStatusTimer();
    }
  }

  void _startStatusTimer() {
    _stopStatusTimer();
    _loadingSeconds = 0;
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _loadingSeconds++;
      if (_isLoading) {
        setState(() {
          _statusText = '${_statusText.split(' ').first} ${_loadingSeconds}s';
        });
      }
    });
  }

  void _stopStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    
    final value = _controller?.value;
    if (value == null) return;
    
    // 检测缓冲状态
    final wasBuffering = _isBuffering;
    _isBuffering = value.isBuffering;
    
    // 计算缓冲速度
    String speedText = '';
    if (value.buffered.isNotEmpty && _lastBufferTime != null) {
      final currentBufferedMs = value.buffered.last.end.inMilliseconds;
      final now = DateTime.now();
      final timeDiff = now.difference(_lastBufferTime!).inMilliseconds;
      
      if (timeDiff > 500 && currentBufferedMs > _lastBufferedMs) {
        final bufferedDiff = currentBufferedMs - _lastBufferedMs;
        // 估算：假设每秒视频约 500KB (4Mbps)
        final estimatedKBps = (bufferedDiff / 1000) * 0.5 * (1000 / timeDiff);
        
        if (estimatedKBps > 1024) {
          speedText = '${(estimatedKBps / 1024).toStringAsFixed(1)} MB/s';
        } else if (estimatedKBps > 0) {
          speedText = '${estimatedKBps.toStringAsFixed(0)} KB/s';
        }
        
        _lastBufferedMs = currentBufferedMs;
        _lastBufferTime = now;
      }
    }
    
    setState(() {
      if (_isBuffering) {
        _statusText = speedText.isNotEmpty ? '缓冲中 $speedText' : '缓冲中...';
      } else if (!_isLoading) {
        _statusText = '';
      }
    });
    
    if (_controller != null && _controller!.value.isPlaying) {
      final position = _controller!.value.position.inSeconds;
      context.read<UserDataProvider>().addHistory(
        widget.video,
        widget.episodes[_currentEpisodeIndex].name,
        position,
      );
    }
  }

  void _toggleFullscreen({bool? landscape}) {
    setState(() {
      if (_isFullscreen && landscape == null) {
        // 退出全屏
        _isFullscreen = false;
        _isLandscape = false;
      } else {
        // 进入全屏
        _isFullscreen = true;
        _isLandscape = landscape ?? true;
      }
    });
    
    if (_isFullscreen) {
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _playEpisode(int index) {
    if (index < 0 || index >= widget.episodes.length) return;
    setState(() => _currentEpisodeIndex = index);
    // 获取该集的保存进度
    final history = context.read<UserDataProvider>().history;
    final historyItem = history.firstWhere(
      (h) => h.video.detailUrl == widget.video.detailUrl && 
             h.episodeName == widget.episodes[index].name,
      orElse: () => HistoryItem(
        video: widget.video,
        episodeName: '',
        position: 0,
        watchedAt: DateTime.now(),
      ),
    );
    _savedPosition = historyItem.position;
    _loadVideo(widget.episodes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800; // macOS 或大屏

    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(child: _buildVideoPlayer()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.video.title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: isDesktop ? _buildDesktopLayout(isDark) : _buildMobileLayout(isDark),
    );
  }

  // macOS 桌面布局：左边选集列表，右边播放器
  Widget _buildDesktopLayout(bool isDark) {
    return Row(
      children: [
        // 左侧选集列表
        Container(
          width: 220,
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '选集',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: widget.episodes.length,
                  itemBuilder: (context, index) {
                    final isPlaying = index == _currentEpisodeIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => _playEpisode(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isPlaying
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? Colors.grey.shade800 : Colors.white),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.episodes[index].name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isPlaying
                                  ? (isDark ? Colors.black : Colors.white)
                                  : (isDark ? Colors.white : Colors.black),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // 右侧播放器
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Center(child: _buildVideoPlayer()),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                color: isDark ? Colors.black : Colors.white,
                child: Text(
                  '正在播放: ${widget.episodes[_currentEpisodeIndex].name}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 移动端布局：上方播放器，下方选集
  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildVideoPlayer(),
        ),
        Expanded(
          child: Container(
            color: isDark ? Colors.black : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '正在播放: ${widget.episodes[_currentEpisodeIndex].name}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '选集',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1.8,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: widget.episodes.length,
                    itemBuilder: (context, index) {
                      final isPlaying = index == _currentEpisodeIndex;
                      return GestureDetector(
                        onTap: () => _playEpisode(index),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isPlaying
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.episodes[index].name,
                            style: TextStyle(
                              fontSize: 12,
                              color: isPlaying
                                  ? (isDark ? Colors.black : Colors.white)
                                  : (isDark ? Colors.white : Colors.black),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer() {
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      onHorizontalDragEnd: (details) {
        if (_controller == null) return;
        final velocity = details.primaryVelocity ?? 0;
        final position = _controller!.value.position;
        if (velocity > 0) {
          _controller!.seekTo(position - const Duration(seconds: 10));
        } else {
          _controller!.seekTo(position + const Duration(seconds: 10));
        }
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频
            if (_controller != null && _controller!.value.isInitialized)
              _isFullscreen
                  ? FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  : Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    ),

            // 加载/缓冲指示器
            if (_isLoading || _isBuffering)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(color: Colors.white, radius: 16),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusText.isNotEmpty ? _statusText : '加载中...',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // 错误提示
            if (_errorMessage != null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 12),
                    CupertinoButton(
                      child: const Text('重试'),
                      onPressed: () => _loadVideo(widget.episodes[_currentEpisodeIndex]),
                    ),
                  ],
                ),
              ),

            // 控制层
            if (_showControls && !_isLoading && _errorMessage == null)
              _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final position = _controller?.value.position ?? Duration.zero;
    final duration = _controller?.value.duration ?? Duration.zero;
    final isPlaying = _controller?.value.isPlaying ?? false;
    final buffered = _controller?.value.buffered ?? [];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 顶部栏 - 只在全屏时显示
          if (_isFullscreen)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.back, color: Colors.white),
                    onPressed: () => _toggleFullscreen(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.video.title} - ${widget.episodes[_currentEpisodeIndex].name}',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    onPressed: _showSpeedPicker,
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),

          // 中间播放按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一集
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: Icon(
                  CupertinoIcons.backward_end_fill,
                  color: _currentEpisodeIndex > 0 ? Colors.white : Colors.white38,
                  size: 28,
                ),
                onPressed: _currentEpisodeIndex > 0
                    ? () => _playEpisode(_currentEpisodeIndex - 1)
                    : null,
              ),
              const SizedBox(width: 20),
              // 快退10秒
              CupertinoButton(
                child: const Icon(CupertinoIcons.gobackward_10, color: Colors.white, size: 32),
                onPressed: () => _controller?.seekTo(position - const Duration(seconds: 10)),
              ),
              const SizedBox(width: 20),
              // 播放/暂停
              CupertinoButton(
                child: Icon(
                  isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  color: Colors.white,
                  size: 48,
                ),
                onPressed: () {
                  if (isPlaying) {
                    _controller?.pause();
                  } else {
                    _controller?.play();
                  }
                },
              ),
              const SizedBox(width: 20),
              // 快进10秒
              CupertinoButton(
                child: const Icon(CupertinoIcons.goforward_10, color: Colors.white, size: 32),
                onPressed: () => _controller?.seekTo(position + const Duration(seconds: 10)),
              ),
              const SizedBox(width: 20),
              // 下一集
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: Icon(
                  CupertinoIcons.forward_end_fill,
                  color: _currentEpisodeIndex < widget.episodes.length - 1 ? Colors.white : Colors.white38,
                  size: 28,
                ),
                onPressed: _currentEpisodeIndex < widget.episodes.length - 1
                    ? () => _playEpisode(_currentEpisodeIndex + 1)
                    : null,
              ),
            ],
          ),

          // 底部进度条
          Padding(
            padding: EdgeInsets.only(
              bottom: _isFullscreen ? 16 : 8,
              left: _isFullscreen ? 16 : 8,
              right: _isFullscreen ? 16 : 8,
            ),
            child: Column(
              children: [
                // 自定义进度条（带缓冲）
                _buildProgressBar(position, duration, buffered),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    if (!_isFullscreen) ...[
                      // 非全屏时显示倍速按钮
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _showSpeedPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(width: 12),
                    // 竖屏全屏按钮
                    GestureDetector(
                      onTap: () {
                        if (_isFullscreen && !_isLandscape) {
                          _toggleFullscreen();
                        } else {
                          _toggleFullscreen(landscape: false);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          _isFullscreen && !_isLandscape 
                              ? CupertinoIcons.fullscreen_exit 
                              : CupertinoIcons.rectangle_arrow_up_right_arrow_down_left,
                          color: _isFullscreen && !_isLandscape ? Colors.blue : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    // 横屏全屏按钮
                    GestureDetector(
                      onTap: () {
                        if (_isFullscreen && _isLandscape) {
                          _toggleFullscreen();
                        } else {
                          _toggleFullscreen(landscape: true);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          _isFullscreen && _isLandscape 
                              ? CupertinoIcons.fullscreen_exit 
                              : CupertinoIcons.arrow_up_left_arrow_down_right,
                          color: _isFullscreen && _isLandscape ? Colors.blue : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(Duration position, Duration duration, List<DurationRange> buffered) {
    final durationMs = duration.inMilliseconds.toDouble();
    final positionMs = position.inMilliseconds.toDouble();
    final progress = durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
    
    // 计算缓冲进度
    double bufferProgress = 0.0;
    if (buffered.isNotEmpty && durationMs > 0) {
      final bufferedEnd = buffered.last.end.inMilliseconds.toDouble();
      bufferProgress = (bufferedEnd / durationMs).clamp(0.0, 1.0);
    }

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || durationMs <= 0) return;
        final localX = details.localPosition.dx;
        final width = box.size.width - 32; // 减去 padding
        final percent = (localX / width).clamp(0.0, 1.0);
        final newPosition = Duration(milliseconds: (durationMs * percent).toInt());
        _controller?.seekTo(newPosition);
      },
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || durationMs <= 0) return;
        final localX = details.localPosition.dx;
        final width = box.size.width - 32;
        final percent = (localX / width).clamp(0.0, 1.0);
        final newPosition = Duration(milliseconds: (durationMs * percent).toInt());
        _controller?.seekTo(newPosition);
      },
      child: Container(
        height: 20,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 背景
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            // 缓冲进度
            FractionallySizedBox(
              widthFactor: bufferProgress,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            // 播放进度
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            // 拖动圆点
            Positioned(
              left: progress * (MediaQuery.of(context).size.width - (_isFullscreen ? 64 : 48)) - 6,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('播放速度'),
        actions: _speeds.map((speed) {
          return CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _playbackSpeed = speed);
              _controller?.setPlaybackSpeed(speed);
              Navigator.pop(context);
            },
            child: Text(
              '${speed}x',
              style: TextStyle(
                fontWeight: speed == _playbackSpeed ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stopStatusTimer();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}
