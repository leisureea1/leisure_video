import 'package:dio/dio.dart';
import '../models/video_item.dart';

class ApiService {
  static const String baseUrl = 'https://movieios.leisureea.cn';
  static const int maxRetries = 3;
  
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// 带重试的请求
  Future<Response<T>> _requestWithRetry<T>(
    Future<Response<T>> Function() request, {
    int retries = maxRetries,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        attempt++;
        return await request();
      } on DioException catch (e) {
        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        final isConnectionError = e.type == DioExceptionType.connectionError;
        
        if ((isTimeout || isConnectionError) && attempt < retries) {
          print('请求超时，第 $attempt 次重试...');
          await Future.delayed(Duration(seconds: attempt)); // 递增延迟
          continue;
        }
        rethrow;
      }
    }
  }

  /// 获取首页推荐
  Future<List<HomeSection>> getHomeRecommend() async {
    try {
      final response = await _requestWithRetry(() => _dio.get('/api/home'));
      final data = response.data['data'] as List? ?? [];
      return data.map((json) => HomeSection.fromJson(json)).toList();
    } catch (e) {
      print('获取首页失败: $e');
      return [];
    }
  }

  /// 获取分类列表
  Future<CategoryResult> getCategoryList(String type, int page) async {
    try {
      final response = await _requestWithRetry(
        () => _dio.get('/api/category', queryParameters: {'type': type, 'page': page}),
      );
      return CategoryResult.fromJson(response.data);
    } catch (e) {
      print('获取分类失败: $e');
      return CategoryResult(items: [], page: 1, totalPages: 1, hasMore: false);
    }
  }

  /// 搜索影视
  Future<List<VideoItem>> search(String keyword) async {
    try {
      final response = await _requestWithRetry(
        () => _dio.get('/api/search', queryParameters: {'keyword': keyword}),
      );
      final data = response.data['data'] as List? ?? [];
      return data.map((json) => VideoItem.fromJson(json)).toList();
    } catch (e) {
      print('搜索失败: $e');
      return [];
    }
  }

  /// 获取详情
  Future<VideoDetail?> getDetail(String detailUrl) async {
    try {
      final response = await _requestWithRetry(
        () => _dio.get('/api/detail', queryParameters: {'url': detailUrl}),
      );
      return VideoDetail.fromJson(response.data);
    } catch (e) {
      print('获取详情失败: $e');
      return null;
    }
  }

  /// 获取播放地址（更长超时 + 重试）
  Future<String?> getPlayUrl(String playUrl) async {
    try {
      final response = await _requestWithRetry(
        () => _dio.get(
          '/api/play',
          queryParameters: {'url': playUrl},
          options: Options(receiveTimeout: const Duration(seconds: 90)),
        ),
        retries: 5, // 播放地址多重试几次
      );
      return response.data['url'];
    } catch (e) {
      print('获取播放地址失败: $e');
      return null;
    }
  }
}

class VideoDetail {
  final VideoItem? info;
  final List<Episode> episodes;
  final List<VideoSource> sources;

  VideoDetail({this.info, this.episodes = const [], this.sources = const []});

  factory VideoDetail.fromJson(Map<String, dynamic> json) => VideoDetail(
    info: json['info'] != null ? VideoItem.fromJson(json['info']) : null,
    episodes: (json['episodes'] as List?)?.map((e) => Episode.fromJson(e)).toList() ?? [],
    sources: (json['sources'] as List?)?.map((s) => VideoSource.fromJson(s)).toList() ?? [],
  );
}

class HomeSection {
  final String title;
  final List<VideoItem> items;

  HomeSection({required this.title, required this.items});

  factory HomeSection.fromJson(Map<String, dynamic> json) => HomeSection(
    title: json['title'] ?? '',
    items: (json['items'] as List?)?.map((e) => VideoItem.fromJson(e)).toList() ?? [],
  );
}

class CategoryResult {
  final List<VideoItem> items;
  final int page;
  final int totalPages;
  final bool hasMore;

  CategoryResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.hasMore,
  });

  factory CategoryResult.fromJson(Map<String, dynamic> json) => CategoryResult(
    items: (json['items'] as List?)?.map((e) => VideoItem.fromJson(e)).toList() ?? [],
    page: json['page'] ?? 1,
    totalPages: json['totalPages'] ?? 1,
    hasMore: json['hasMore'] ?? false,
  );
}
