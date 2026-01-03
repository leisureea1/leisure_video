import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video_item.dart';

class VideoCard extends StatelessWidget {
  final VideoItem video;
  final double? width;
  final double? height;
  final bool showTitle;

  const VideoCard({
    super.key,
    required this.video,
    this.width,
    this.height,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: height,
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                child: video.cover != null
                    ? CachedNetworkImage(
                        imageUrl: video.cover!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                          child: const Center(
                            child: CupertinoActivityIndicator(),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                          child: Icon(
                            CupertinoIcons.film,
                            color: Colors.grey.shade500,
                            size: 32,
                          ),
                        ),
                      )
                    : Icon(
                        CupertinoIcons.film,
                        color: Colors.grey.shade500,
                        size: 32,
                      ),
              ),
            ),
          ),
          
          // 标题
          if (showTitle) ...[
            const SizedBox(height: 8),
            Text(
              video.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
