import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../theme/tokens.dart';

/// Tile OpenStreetMap (tanpa API key). Mode gelap memakai filter bawaan flutter_map.
Widget osmTiles(BuildContext context) => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'id.polmas.polmas_keamanan',
  tileBuilder: context.isDark ? darkModeTileBuilder : null,
);

/// Atribusi OSM wajib ditampilkan.
Widget osmAttribution() => const RichAttributionWidget(showFlutterMapAttribution: false, attributions: [TextSourceAttribution('© OpenStreetMap')]);

const indonesiaCenter = LatLng(-2.5, 118.0);

/// Penanda berdenyut: cincin membesar & memudar (1200 ms berulang).
class PulseMarker extends StatefulWidget {
  const PulseMarker({super.key, this.color = PK.red, this.size = 22, this.icon});
  final Color color;
  final double size;
  final IconData? icon;
  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: PK.sosPulse)..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Stack(
        alignment: Alignment.center,
        children: [
          if (!reduce)
            Container(
              width: widget.size * (1 + 1.6 * _c.value),
              height: widget.size * (1 + 1.6 * _c.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
            ),
            child: widget.icon == null ? null : Icon(widget.icon, color: Colors.white, size: widget.size * 0.55),
          ),
        ],
      ),
    );
  }
}

/// Gerakkan peta mulus dari posisi sekarang ke [to] (zoom & tengah diinterpolasi).
Future<void> animateMapTo(MapController map, TickerProvider vsync, LatLng to, double zoom, {Duration duration = PK.mapZoom, bool reduce = false}) async {
  if (reduce) {
    map.move(to, zoom);
    return;
  }
  final cam = map.camera;
  final lat = Tween(begin: cam.center.latitude, end: to.latitude);
  final lng = Tween(begin: cam.center.longitude, end: to.longitude);
  final z = Tween(begin: cam.zoom, end: zoom);
  final c = AnimationController(vsync: vsync, duration: duration);
  final a = CurvedAnimation(parent: c, curve: Curves.easeOut);
  c.addListener(() => map.move(LatLng(lat.evaluate(a), lng.evaluate(a)), z.evaluate(a)));
  await c.forward();
  c.dispose();
}
