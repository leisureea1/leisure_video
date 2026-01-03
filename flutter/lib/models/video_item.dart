class VideoItem {
  final String title;
  final String? cover;
  final String? description;
  final List<String> tags;
  final String detailUrl;
  final String? year;
  final String? rating;
  final String? director;
  final List<String> actors;
  final String? status;
  final String? category;

  VideoItem({
    required this.title,
    this.cover,
    this.description,
    this.tags = const [],
    required this.detailUrl,
    this.year,
    this.rating,
    this.director,
    this.actors = const [],
    this.status,
    this.category,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    title: json['title'] ?? '未知',
    cover: json['cover'],
    description: json['description'],
    tags: List<String>.from(json['tags'] ?? []),
    detailUrl: json['detailUrl'] ?? '',
    year: json['year'],
    rating: json['rating'],
    director: json['director'],
    actors: List<String>.from(json['actors'] ?? []),
    status: json['status'],
    category: json['category'],
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'cover': cover,
    'description': description,
    'tags': tags,
    'detailUrl': detailUrl,
    'year': year,
    'rating': rating,
    'director': director,
    'actors': actors,
    'status': status,
    'category': category,
  };
}

class Episode {
  final String name;
  final String link;

  Episode({required this.name, required this.link});

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    name: json['name'] ?? '',
    link: json['link'] ?? '',
  );
}

class VideoSource {
  final String name;
  final String pageUrl;
  final List<Episode> episodes;

  VideoSource({required this.name, required this.pageUrl, this.episodes = const []});

  factory VideoSource.fromJson(Map<String, dynamic> json) => VideoSource(
    name: json['name'] ?? '默认',
    pageUrl: json['pageUrl'] ?? '',
    episodes: (json['episodes'] as List?)?.map((e) => Episode.fromJson(e)).toList() ?? [],
  );
}
