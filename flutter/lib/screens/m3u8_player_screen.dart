import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

class M3u8PlayerScreen extends StatefulWidget {
  const M3u8PlayerScreen({super.key});

  @override
  State<M3u8PlayerScreen> createState() => _M3u8PlayerScreenState();
}

class _M3u8PlayerScreenState extends State<M3u8PlayerScreen> {
  final TextEditingController _urlController = TextEditingController();
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isPlaying = false;
  String? _errorMessage;
  String _statusText = '';
  List<String> _urlHistory = [];
  
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _loadUrlHistory();
  }

  Future<void> _loadUrlHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlHistory = prefs.getStringList('m3u8_history') ?? [];
    });
  }

  Future<void> _saveUrlHistory(String url) async {
    if (url.trim().isEmpty) return;
    _urlHistory.remove(url);
    _urlHistory.insert(0, url);
    if (_urlHistory.length > 10) {
      _urlHistory = _urlHistory.take(10).toList();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('m3u8_history', _urlHistory);
    setState(() {});
  }

  Future<void> _playUrl(String url) async {
    if (url.trim().isEmpty) return;
    
    // 简单验证 URL
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _errorMessage = '请输入有效的 URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusText = '连接中...';
    });

    try {
      _controller?.dispose();
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      
      setState(() => _statusText = '加载视频...');
      
      await _controller!.initialize();
      _controller!.play();
      _controller!.addListener(_onVideoUpdate);
      
      await _saveUrlHistory(url);

      setState(() {
        _isLoading = false;
        _isPlaying = true;
        _statusText = '';
      });
      
      _startHideControlsTimer();
    } catch (e) {
      setState(() {
        _errorMessage = '播放失败: ${e.toString().split(':').last.trim()}';
        _isLoading = false;
      });
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isFullscreen && _isPlaying) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(child: _buildVideoPlayer()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        title: Text(
          'M3U8 播放器',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // URL 输入框
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: '输入 M3U8 或视频链接',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: Icon(CupertinoIcons.link, color: Colors.grey.shade500),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Icon(CupertinoIcons.doc_on_clipboard, color: Colors.grey.shade500, size: 20),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _urlController.text = data!.text!;
                            setState(() {});
                          }
                        },
                      ),
                      if (_urlController.text.isNotEmpty)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: Icon(CupertinoIcons.clear_circled_solid, color: Colors.grey.shade400, size: 18),
                          onPressed: () {
                            _urlController.clear();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                onSubmitted: _playUrl,
              ),
            ),
            const SizedBox(height: 12),
            
            // 播放按钮
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(12),
                onPressed: _urlController.text.isNotEmpty
                    ? () => _playUrl(_urlController.text)
                    : null,
                child: const Text('播放', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),

            // 播放器区域
            if (_isPlaying || _isLoading || _errorMessage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildVideoPlayer(),
                ),
              ),

            // 历史记录
            if (_urlHistory.isNotEmpty && !_isPlaying) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '播放历史',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    child: Text('清空', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('m3u8_history');
                      setState(() => _urlHistory = []);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...(_urlHistory.map((url) => _buildHistoryItem(url, isDark))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(String url, bool isDark) {
    return GestureDetector(
      onTap: () {
        _urlController.text = url;
        _playUrl(url);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.play_circle, color: Colors.grey.shade500, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                url,
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
        if (_showControls) _startHideControlsTimer();
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),

            // 加载中
            if (_isLoading)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(color: Colors.white, radius: 16),
                    const SizedBox(height: 12),
                    Text(_statusText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),

            // 错误
            if (_errorMessage != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.white54)),
                  ],
                ),
              ),

            // 控制层
            if (_showControls && _isPlaying && !_isLoading)
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
          // 顶部
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (_isFullscreen)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.back, color: Colors.white),
                    onPressed: _toggleFullscreen,
                  ),
                const Spacer(),
              ],
            ),
          ),

          // 中间播放按钮
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
              _startHideControlsTimer();
            },
          ),

          // 底部进度条
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: position.inSeconds.toDouble(),
                    max: duration.inSeconds.toDouble().clamp(1, double.infinity),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (value) {
                      _controller?.seekTo(Duration(seconds: value.toInt()));
                      _startHideControlsTimer();
                    },
                  ),
                ),
                Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    _isFullscreen ? CupertinoIcons.fullscreen_exit : CupertinoIcons.fullscreen,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ],
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
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    _urlController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}
