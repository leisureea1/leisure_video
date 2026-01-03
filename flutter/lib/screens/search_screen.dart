import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';
import '../widgets/video_card.dart';
import 'detail_screen.dart';
import 'm3u8_player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final ApiService _api = ApiService();
  final FocusNode _focusNode = FocusNode();
  
  List<VideoItem> _results = [];
  List<String> _searchHistory = [];
  bool _isLoading = false;
  String _searchedKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchHistory = prefs.getStringList('search_history') ?? [];
    });
  }

  Future<void> _saveSearchHistory(String keyword) async {
    if (keyword.trim().isEmpty) return;
    _searchHistory.remove(keyword);
    _searchHistory.insert(0, keyword);
    if (_searchHistory.length > 20) {
      _searchHistory = _searchHistory.take(20).toList();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _searchHistory);
    setState(() {});
  }

  Future<void> _clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    setState(() => _searchHistory = []);
  }

  Future<void> _search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _searchedKeyword = keyword;
    });
    
    _focusNode.unfocus();
    await _saveSearchHistory(keyword);
    
    final results = await _api.search(keyword);
    
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: CustomScrollView(
        slivers: [
          // 搜索栏
          SliverAppBar(
            pinned: true,
            floating: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            toolbarHeight: 60,
            title: Container(
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: '搜索影视、演员、导演...',
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                  prefixIcon: Icon(CupertinoIcons.search, color: Colors.grey.shade500, size: 20),
                  suffixIcon: _controller.text.isNotEmpty
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: Icon(CupertinoIcons.clear_circled_solid, 
                            color: Colors.grey.shade400, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _results = [];
                              _searchedKeyword = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: const TextStyle(fontSize: 15),
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            actions: [
              CupertinoButton(
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(CupertinoIcons.link, size: 22),
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => const M3u8PlayerScreen()),
                ),
              ),
            ],
          ),
          
          // 搜索结果或历史记录
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_results.isEmpty && _searchedKeyword.isNotEmpty)
            SliverFillRemaining(child: _buildNoResults())
          else if (_results.isEmpty)
            SliverToBoxAdapter(child: _buildSearchHistoryAndHint())
          else
            _buildResults(),
        ],
      ),
    );
  }

  Widget _buildSearchHistoryAndHint() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 搜索历史
        if (_searchHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  child: Text(
                    '清空',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  ),
                  onPressed: _confirmClearHistory,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _searchHistory.map((keyword) {
                return GestureDetector(
                  onTap: () {
                    _controller.text = keyword;
                    _search(keyword);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      keyword,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
        
        // 提示
        Center(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(CupertinoIcons.search, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                '搜索你想看的影视',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '支持片名、演员、导演搜索',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              const SizedBox(height: 24),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.link, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('播放 M3U8 链接', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => const M3u8PlayerScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmClearHistory() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空所有搜索历史吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('清空'),
            onPressed: () {
              _clearSearchHistory();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.doc_text_search, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '未找到 "$_searchedKeyword" 相关内容',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '换个关键词试试',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final crossAxisCount = width > 900 ? 6 : (width > 600 ? 4 : 3);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.55,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => DetailScreen(video: _results[index]),
                  ),
                ),
                child: VideoCard(video: _results[index]),
              ),
              childCount: _results.length,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
