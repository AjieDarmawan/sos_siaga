import 'package:flutter/material.dart';

import '../core/format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

(IconData, Color, String) newsStyle(String category) => switch (category) {
  'imbauan' => (Icons.campaign_rounded, PK.gold, 'Imbauan'),
  'pengumuman' => (Icons.announcement_rounded, PK.navy, 'Pengumuman'),
  _ => (Icons.newspaper_rounded, PK.green, 'Kabar'),
};

/// Kartu kabar: gambar kecil (ikon kategori), judul, ringkasan, waktu.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.news});
  final Map news;
  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = newsStyle(news['category'] as String);
    final t = Theme.of(context).textTheme;
    final at = DateTime.parse(news['published_at'] as String).toLocal();
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewsScreen(news: news))),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withValues(alpha: 0.85), color]),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.ink2),
                    ),
                    const Spacer(),
                    if (news['is_demo'] == true) const DemoTag(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(news['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                const SizedBox(height: 2),
                if (news['summary'] != null)
                  Text(
                    news['summary'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(color: context.ink2),
                  ),
                const SizedBox(height: 4),
                Text(fmtRelative(at), style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key, required this.news});
  final Map news;
  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = newsStyle(news['category'] as String);
    final t = Theme.of(context).textTheme;
    final kec = news['kecamatan'] as Map?;
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PK.rCard),
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.8), color]),
            ),
            child: Icon(icon, color: Colors.white, size: 64),
          ),
          const SizedBox(height: 16),
          Text(news['title'] as String, style: t.headlineSmall),
          const SizedBox(height: 6),
          Text(
            [
              news['author'] ?? 'Polmas',
              fmtDateTime(DateTime.parse(news['published_at'] as String).toLocal()),
              kec != null ? 'Kec. ${kec['name']}' : 'Semua wilayah',
            ].join(' · '),
            style: t.bodySmall,
          ),
          const SizedBox(height: 16),
          Text((news['body'] ?? news['summary'] ?? '') as String, style: t.bodyLarge),
        ],
      ),
    );
  }
}
