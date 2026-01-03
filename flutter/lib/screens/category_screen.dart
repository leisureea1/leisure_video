import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';
import '../widgets/video_card.dart';
import 'detail_screen.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();
  
  int _selectedCategory = 0;
  bool _isGridView = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  
  List<VideoItem> _videos = [];
  int _currentPage = 1;
  bool _hasMore = true;
  
  final List<Map<String, String>> _categories = [
    {'name': '电视剧', 'type': 'tv'},
    {'name': '电影', 'type': 'movie'},
    {'name': '动漫', 'type': 'anime'},
    {'name': '短剧', 'type': 'playlet'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _videos = [];
    });

    final type = _categories[_selectedCategory]['type']!;
    final result = await _api.getCategoryList(type, 1);
    
    setState(() {
      _videos = result.items;
      _hasMore = result.hasMore;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);
    
    final type = _categories[_selectedCategory]['type']!;
    final result = await _api.getCategoryList(type, _currentPage + 1);
    
    setState(() {
      _videos.addAll(result.items);
      _currentPage = result.page;
      _hasMore = result.hasMore;
      _isLoadingMore = false;
    });
  }

  void _onCategoryChanged(int index) {
    if (_selectedCategory == index) return;
    setState(() => _selectedCategory = index);
    _scrollController.jumpTo(0);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('分类'),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: Icon(
                _isGridView ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
                size: 22,
              ),
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
          ),
          
          // 分类标签
          SliverToBoxAdapter(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedCategory == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => _onCategoryChanged(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _categories[index]['name']!,
                          style: TextStyle(
                            color: isSelected
                                ? (isDark ? Colors.black : Colors.white)
                                : (isDark ? Colors.white : Colors.black),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // 内容区域
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_videos.isEmpty)
            SliverFillRemaining(child: _buildEmptyState())
          else if (_isGridView)
            _buildGridView()
          else
            _buildListView(),
          
          // 加载更多指示器
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            ),
          
          // 底部间距
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.film, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无${_categories[_selectedCategory]['name']}内容',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 16),
          CupertinoButton(
            child: const Text('重试'),
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.55,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => GestureDetector(
            onTap: () => _openDetail(_videos[index]),
            child: VideoCard(video: _videos[index]),
          ),
          childCount: _videos.length,
        ),
      ),
    );
  }

  Widget _buildListView() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildListItem(_videos[index]),
        childCount: _videos.length,
      ),
    );
  }

  Widget _buildListItem(VideoItem video) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => _openDetail(video),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 100,
                height: 140,
                color: Colors.grey.shade300,
                child: video.cover != null && video.cover!.isNotEmpty
                    ? Image.network(
                        video.cover!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          CupertinoIcons.film,
                          color: Colors.grey.shade500,
                        ),
                      )
                    : Icon(CupertinoIcons.film, color: Colors.grey.shade500),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (video.tags.isNotEmpty)
                    Text(
                      video.tags.take(3).join(' · '),
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  const SizedBox(height: 4),
                  if (video.description != null && video.description!.isNotEmpty)
                    Text(
                      video.description!,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(VideoItem video) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => DetailScreen(video: video)),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
