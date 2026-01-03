import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';
import '../providers/user_data_provider.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final VideoItem video;

  const DetailScreen({super.key, required this.video});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final ApiService _api = ApiService();
  VideoDetail? _detail;
  bool _isLoading = true;
  int _selectedSource = 0;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final detail = await _api.getDetail(widget.video.detailUrl);
    setState(() {
      _detail = detail;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userData = context.watch<UserDataProvider>();
    final isFavorite = userData.isFavorite(widget.video.detailUrl);
    final isInWatchlist = userData.isInWatchlist(widget.video.detailUrl);
    final info = _detail?.info ?? widget.video;
    // 优先使用详情页返回的封面，否则用传入的封面
    final coverUrl = info.cover ?? widget.video.cover;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部海报区域
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: isDark ? Colors.black : Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl != null && coverUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey.shade800),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade800,
                        child: const Icon(CupertinoIcons.film, size: 64, color: Colors.white54),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey.shade800,
                      child: const Icon(CupertinoIcons.film, size: 64, color: Colors.white54),
                    ),
                  // 渐变遮罩
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                  // 标题
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Text(
                      info.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 操作按钮
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: CupertinoIcons.play_fill,
                      label: '播放',
                      isPrimary: true,
                      onTap: () => _playEpisode(0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                    label: '收藏',
                    isActive: isFavorite,
                    onTap: () => userData.toggleFavorite(widget.video),
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: isInWatchlist ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.plus_circle,
                    label: '追剧',
                    isActive: isInWatchlist,
                    onTap: () => userData.toggleWatchlist(widget.video),
                  ),
                ],
              ),
            ),
          ),

          // 标签
          if (info.tags.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: info.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(tag, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                  )).toList(),
                ),
              ),
            ),

          // 简介
          if (info.description != null && info.description!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('简介', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      info.description!,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),

          // 选集
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            )
          else if (_detail != null && _detail!.episodes.isNotEmpty)
            SliverToBoxAdapter(child: _buildEpisodes()),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildEpisodes() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final episodes = _detail!.episodes;
    final sources = _detail!.sources;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('选集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              if (sources.length > 1)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Row(
                    children: [
                      Text(sources[_selectedSource].name, style: const TextStyle(fontSize: 14)),
                      const Icon(CupertinoIcons.chevron_down, size: 16),
                    ],
                  ),
                  onPressed: () => _showSourcePicker(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(episodes.length, (index) {
              return GestureDetector(
                onTap: () => _playEpisode(index),
                child: Container(
                  width: 70,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    episodes[index].name,
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showSourcePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择线路'),
        actions: _detail!.sources.asMap().entries.map((entry) {
          return CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _selectedSource = entry.key);
              Navigator.pop(context);
            },
            child: Text(entry.value.name),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _playEpisode(int index) {
    if (_detail == null || _detail!.episodes.isEmpty) return;
    final episode = _detail!.episodes[index];
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => PlayerScreen(
          video: widget.video,
          episode: episode,
          episodes: _detail!.episodes,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isActive;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isPrimary
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isPrimary
                  ? (isDark ? Colors.black : Colors.white)
                  : isActive
                      ? Colors.red
                      : (isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isPrimary
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
