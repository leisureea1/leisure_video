import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_item.dart';

class UserDataProvider extends ChangeNotifier {
  List<VideoItem> _favorites = [];
  List<VideoItem> _watchlist = [];
  List<HistoryItem> _history = [];
  
  List<VideoItem> get favorites => _favorites;
  List<VideoItem> get watchlist => _watchlist;
  List<HistoryItem> get history => _history;
  
  UserDataProvider() {
    _loadData();
  }
  
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final favJson = prefs.getStringList('favorites') ?? [];
    _favorites = favJson.map((s) => VideoItem.fromJson(jsonDecode(s))).toList();
    
    final watchJson = prefs.getStringList('watchlist') ?? [];
    _watchlist = watchJson.map((s) => VideoItem.fromJson(jsonDecode(s))).toList();
    
    final histJson = prefs.getStringList('history') ?? [];
    _history = histJson.map((s) => HistoryItem.fromJson(jsonDecode(s))).toList();
    
    notifyListeners();
  }
  
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', _favorites.map((v) => jsonEncode(v.toJson())).toList());
    await prefs.setStringList('watchlist', _watchlist.map((v) => jsonEncode(v.toJson())).toList());
    await prefs.setStringList('history', _history.map((h) => jsonEncode(h.toJson())).toList());
  }
  
  bool isFavorite(String detailUrl) => _favorites.any((v) => v.detailUrl == detailUrl);
  bool isInWatchlist(String detailUrl) => _watchlist.any((v) => v.detailUrl == detailUrl);
  
  Future<void> toggleFavorite(VideoItem item) async {
    if (isFavorite(item.detailUrl)) {
      _favorites.removeWhere((v) => v.detailUrl == item.detailUrl);
    } else {
      _favorites.insert(0, item);
    }
    await _saveData();
    notifyListeners();
  }
  
  Future<void> toggleWatchlist(VideoItem item) async {
    if (isInWatchlist(item.detailUrl)) {
      _watchlist.removeWhere((v) => v.detailUrl == item.detailUrl);
    } else {
      _watchlist.insert(0, item);
    }
    await _saveData();
    notifyListeners();
  }
  
  Future<void> addHistory(VideoItem item, String episodeName, int position) async {
    _history.removeWhere((h) => h.video.detailUrl == item.detailUrl);
    _history.insert(0, HistoryItem(
      video: item,
      episodeName: episodeName,
      position: position,
      watchedAt: DateTime.now(),
    ));
    if (_history.length > 100) _history = _history.take(100).toList();
    await _saveData();
    notifyListeners();
  }
  
  Future<void> clearHistory() async {
    _history.clear();
    await _saveData();
    notifyListeners();
  }
}

class HistoryItem {
  final VideoItem video;
  final String episodeName;
  final int position;
  final DateTime watchedAt;
  
  HistoryItem({
    required this.video,
    required this.episodeName,
    required this.position,
    required this.watchedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'video': video.toJson(),
    'episodeName': episodeName,
    'position': position,
    'watchedAt': watchedAt.toIso8601String(),
  };
  
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    video: VideoItem.fromJson(json['video']),
    episodeName: json['episodeName'] ?? '',
    position: json['position'] ?? 0,
    watchedAt: DateTime.parse(json['watchedAt']),
  );
}
