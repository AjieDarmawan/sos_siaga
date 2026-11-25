import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/format.dart';
import '../core/models.dart';
import '../screens/incident_screen.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'map_widgets.dart';

/// Peta titik kejadian dengan klaster per sel layar (FR-09). Penanda merah = SOS, biru navy = laporan.
/// Ketuk klaster untuk memperbesar, ketuk titik untuk pratinjau lalu buka detail.
class IncidentMap extends StatefulWidget {
  const IncidentMap({super.key, required this.reports, this.center});
  final List<Report> reports;
  final LatLng? center;
  @override
  State<IncidentMap> createState() => _IncidentMapState();
}

class _Cluster {
  _Cluster(this.items);
  final List<Report> items;
  LatLng get center {
    final lat = items.map((r) => r.location!.lat).reduce((a, b) => a + b) / items.length;
    final lng = items.map((r) => r.location!.lng).reduce((a, b) => a + b) / items.length;
    return LatLng(lat, lng);
  }

  bool get hasSos => items.any((r) => r.isSos && r.status == PkStatus.baru);
}

class _IncidentMapState extends State<IncidentMap> with TickerProviderStateMixin {
  final _map = MapController();
  double _zoom = 14;
  Report? _preview;

  List<Report> get _withLoc => widget.reports.where((r) => r.location != null).toList();

  LatLng get _initial {
    if (widget.center != null) return widget.center!;
    final l = _withLoc;
    if (l.isEmpty) return const LatLng(-6.5971, 106.7973);
    return _Cluster(l).center;
  }

  /// Kelompokkan titik dalam sel ±56 px pada zoom sekarang.
  List<_Cluster> _clusters() {
    final cellDeg = 360 / (256 * math.pow(2, _zoom)) * 56;
    final cells = <String, List<Report>>{};
    for (final r in _withLoc) {
      final k = '${(r.location!.lat / cellDeg).floor()}:${(r.location!.lng / cellDeg).floor()}';
      (cells[k] ??= []).add(r);
    }
    return cells.values.map(_Cluster.new).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clusters = _clusters();
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _initial,
            initialZoom: 14,
            minZoom: 5,
            maxZoom: 18,
            onTap: (_, _) => setState(() => _preview = null),
            onPositionChanged: (cam, _) {
              if ((cam.zoom - _zoom).abs() >= 0.5) setState(() => _zoom = cam.zoom);
            },
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            osmTiles(context),
            MarkerLayer(
              markers: [
                for (final c in clusters)
                  if (c.items.length == 1)
                    Marker(
                      point: c.center,
                      width: 48,
                      height: 48,
                      child: Semantics(
                        button: true,
                        label: '${c.items.first.isSos ? 'SOS' : 'Laporan'} ${c.items.first.headline}',
                        child: GestureDetector(
                          onTap: () => setState(() => _preview = c.items.first),
                          child: _Pin(r: c.items.first, selected: _preview?.id == c.items.first.id),
                        ),
                      ),
                    )
                  else
                    Marker(
                      point: c.center,
                      width: 56,
                      height: 56,
                      child: Semantics(
                        button: true,
                        label: '${c.items.length} kejadian, ketuk untuk memperbesar',
                        child: GestureDetector(
                          onTap: () => animateMapTo(
                            _map,
                            this,
                            c.center,
                            math.min(_zoom + 2, 18),
                            duration: const Duration(milliseconds: 450),
                            reduce: context.reduceMotion,
                          ),
                          child: _ClusterBubble(count: c.items.length, sos: c.hasSos),
                        ),
                      ),
                    ),
              ],
            ),
            osmAttribution(),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: context.surface.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(10), boxShadow: PK.cardShadow),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(color: context.danger),
                const SizedBox(width: 4),
                Text('SOS', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink)),
                const SizedBox(width: 12),
                _Dot(color: PK.navy),
                const SizedBox(width: 4),
                Text('Laporan', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink)),
                const SizedBox(width: 12),
                Text('${_withLoc.length} titik', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        if (_withLoc.isEmpty) const Center(child: AppCard(child: Text('Belum ada titik kejadian pada filter ini.'))),
        AnimatedPositioned(
          duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          left: 12,
          right: 12,
          bottom: _preview == null ? -200 : 12,
          child: _preview == null ? const SizedBox.shrink() : IncidentCard(report: _preview!, onTap: () => openIncident(context, _preview!.id)),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.r, required this.selected});
  final Report r;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final color = r.isSos ? PK.red : PK.navy;
    if (r.isSos && r.status == PkStatus.baru) return PulseMarker(color: color, size: 24, icon: Icons.sos_rounded);
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: selected ? 32 : 24,
        height: selected ? 32 : 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
        ),
        child: Icon(r.isSos ? Icons.sos_rounded : categoryIcon(r.category), size: selected ? 16 : 12, color: Colors.white),
      ),
    );
  }
}

class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count, required this.sos});
  final int count;
  final bool sos;
  @override
  Widget build(BuildContext context) {
    final size = 34.0 + math.min(18, count.toDouble());
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: (sos ? PK.red : PK.navy).withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: sos ? PK.sosGlow : const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
        ),
        alignment: Alignment.center,
        child: Text(
          fmtNumber(count),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }
}
