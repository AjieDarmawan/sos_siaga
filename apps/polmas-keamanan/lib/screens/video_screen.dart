import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/format.dart';

/// Pemutar bukti video di dalam aplikasi (FR-06). URL presigned berlaku ±15 menit.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.url, required this.title, this.subtitle});
  final String url;
  final String title;
  final String? subtitle;
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  String? _error;

  @override
  void initState() {
    super.initState();
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _c.play();
        })
        .catchError((Object _) {
          if (mounted) setState(() => _error = 'Video tidak bisa diputar. Tautan mungkin sudah kedaluwarsa, buka ulang dari laporan.');
        });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (widget.subtitle != null) Text(widget.subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      )
                    : !v.isInitialized
                    ? const CircularProgressIndicator(color: Colors.white)
                    : GestureDetector(
                        onTap: () => v.isPlaying ? _c.pause() : _c.play(),
                        child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)),
                      ),
              ),
            ),
            if (v.isInitialized)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: v.isPlaying ? 'Jeda' : 'Putar',
                      iconSize: 36,
                      color: Colors.white,
                      icon: Icon(v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                      onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(_c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFFD71920))),
                    ),
                    const SizedBox(width: 12),
                    Text('${fmtClock(v.position)} / ${fmtClock(v.duration)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String fmtClock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

// Dipakai juga oleh galeri video.
String fmtVideoAge(DateTime d) => fmtRelative(d);
