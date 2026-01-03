import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_data_provider.dart';
import '../widgets/video_card.dart';
import 'detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userData = context.watch<UserDataProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return CustomScrollView(
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: const Text('我的'),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
          border: null,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Icon(CupertinoIcons.gear, size: 22),
            onPressed: () => _showSettings(context, themeProvider),
          ),
        ),

        // 统计卡片
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(count: userData.favorites.length, label: '收藏'),
                _StatItem(count: userData.watchlist.length, label: '追剧'),
                _StatItem(count: userData.history.length, label: '历史'),
              ],
            ),
          ),
        ),

        // Tab 栏
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: isDark ? Colors.white : Colors.black,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: '收藏'),
                Tab(text: '追剧'),
                Tab(text: '历史'),
              ],
              onTap: (_) => setState(() {}),
            ),
          ),
        ),

        // 内容
        SliverFillRemaining(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFavorites(userData),
              _buildWatchlist(userData),
              _buildHistory(userData),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFavorites(UserDataProvider userData) {
    if (userData.favorites.isEmpty) {
      return _buildEmptyState('暂无收藏', '收藏喜欢的影视，方便下次观看');
    }
    return _buildGrid(userData.favorites);
  }

  Widget _buildWatchlist(UserDataProvider userData) {
    if (userData.watchlist.isEmpty) {
      return _buildEmptyState('暂无追剧', '添加想追的剧集，不错过更新');
    }
    return _buildGrid(userData.watchlist);
  }

  Widget _buildHistory(UserDataProvider userData) {
    if (userData.history.isEmpty) {
      return _buildEmptyState('暂无历史', '观看记录会显示在这里');
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: userData.history.length,
      itemBuilder: (context, index) {
        final item = userData.history[index];
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => DetailScreen(video: item.video)),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 80,
                    height: 110,
                    color: Colors.grey.shade300,
                    child: item.video.cover != null
                        ? Image.network(item.video.cover!, fit: BoxFit.cover)
                        : const Icon(CupertinoIcons.film),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.video.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '看到 ${item.episodeName}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(item.watchedAt),
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(List videos) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => DetailScreen(video: videos[index])),
        ),
        child: VideoCard(video: videos[index]),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.film, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context, ThemeProvider themeProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('设置'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              themeProvider.setThemeMode(ThemeMode.light);
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('浅色模式'),
                if (themeProvider.themeMode == ThemeMode.light)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              themeProvider.setThemeMode(ThemeMode.dark);
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('深色模式'),
                if (themeProvider.themeMode == ThemeMode.dark)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              themeProvider.setThemeMode(ThemeMode.system);
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('跟随系统'),
                if (themeProvider.themeMode == ThemeMode.system)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _confirmClearHistory(context);
            },
            child: const Text('清除历史记录'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清除历史记录'),
        content: const Text('确定要清除所有观看历史吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('清除'),
            onPressed: () {
              context.read<UserDataProvider>().clearHistory();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}月${time.day}日';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;

  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ],
    );
  }
}
