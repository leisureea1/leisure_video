import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/video_card.dart';
import '../widgets/section_header.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  List<HomeSection> _sections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final sections = await _api.getHomeRecommend();
    setState(() {
      _sections = sections;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('发现'),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
            border: null,
            heroTag: 'home_nav',
          ),

          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_sections.isEmpty)
            SliverFillRemaining(child: _buildEmptyState())
          else
            ..._sections.asMap().entries.map((entry) {
              final index = entry.key;
              final section = entry.value;
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(title: section.title, showMore: false),
                    SizedBox(
                      height: index == 0 ? 220 : 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: section.items.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () => _openDetail(section.items[i]),
                            child: VideoCard(
                              video: section.items[i],
                              width: index == 0 ? 150 : 110,
                              height: index == 0 ? 200 : 160,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  void _openDetail(VideoItem video) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => DetailScreen(video: video)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.film, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('加载失败', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 12),
          CupertinoButton(
            child: const Text('重试'),
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }
}
