import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';

/// Komponen tampilan mockup Opsi A (docs/mockups/polmas-digital.html): header navy bergaris, lambang perisai-bintang,
/// kartu laporan dengan kolom Tindak Lanjut, pil status, chip ekosistem, panel analitik.

// ------------------------------------------------------------------ lambang

/// Lambang perisai-bintang generik (bukan logo resmi Polri): perisai navy bergaris emas, bintang, dua sulur.
class PolmasEmblem extends StatelessWidget {
  const PolmasEmblem({super.key, this.size = 64, this.fill = PK.navy, this.line = PK.gold, this.star = PK.gold});
  final double size;
  final Color fill, line, star;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Lambang Polmas Digital',
    child: CustomPaint(size: Size(size, size * 72 / 64), painter: _EmblemPainter(fill, line, star)),
  );
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.fill, this.line, this.star);
  final Color fill, line, star;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 72);
    Path shield(double t) => Path()
      ..moveTo(32, 2 + t * 6.5)
      ..lineTo(60 - t * 6, 12 + t * 4.5)
      ..lineTo(60 - t * 6, 34)
      ..cubicTo(60 - t * 6, 52 - t * 4.5, 47 - t * 2.5, 64 - t * 6.5, 32, 70 - t * 7)
      ..cubicTo(17 + t * 2.5, 64 - t * 6.5, 4 + t * 6, 52 - t * 4.5, 4 + t * 6, 34)
      ..lineTo(4 + t * 6, 12 + t * 4.5)
      ..close();
    canvas.drawPath(shield(0), Paint()..color = fill);
    canvas.drawPath(
      shield(0),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      shield(1),
      Paint()
        ..color = line.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    const pts = <double>[32, 18, 35.5, 27.6, 45.3, 27.7, 37.6, 33.9, 40.2, 43.3, 32, 37.8, 23.8, 43.3, 26.4, 33.9, 18.7, 27.7, 28.5, 27.6];
    final starPath = Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i < pts.length; i += 2) {
      starPath.lineTo(pts[i], pts[i + 1]);
    }
    canvas.drawPath(starPath..close(), Paint()..color = star);
    final vine = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()
      ..moveTo(19, 47)
      ..cubicTo(22.5, 51.5, 27, 54.4, 32, 55.6), vine);
    canvas.drawPath(Path()
      ..moveTo(45, 47)
      ..cubicTo(41.5, 51.5, 37, 54.4, 32, 55.6), vine);
  }

  @override
  bool shouldRepaint(_EmblemPainter o) => o.fill != fill || o.line != line || o.star != star;
}

// ------------------------------------------------------------------ header navy

/// Garis diagonal halus di atas navy (pola seragam).
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x09FFFFFF)
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Header navy bergradasi + garis diagonal, sudut bawah membulat. Mengisi area status bar.
class NavyHeader extends StatelessWidget {
  const NavyHeader({super.key, required this.child, this.radius = 30, this.padding = const EdgeInsets.fromLTRB(18, 6, 18, 20)});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment(-0.6, -1), end: Alignment(0.6, 1), colors: [PK.navyMid, PK.navy2]),
        ),
        child: CustomPaint(
          painter: _StripePainter(),
          child: Padding(
            padding: padding.copyWith(top: padding.top + top),
            child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
          ),
        ),
      ),
    );
  }
}

/// Tombol ikon kotak transparan di header navy (lonceng, kembali, menu).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.tooltip, this.onTap, this.dot = false, this.size = 42});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool dot;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 21),
              if (dot)
                Positioned(
                  top: 9,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF04438),
                      shape: BoxShape.circle,
                      border: Border.all(color: PK.navy, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ label kecil

/// "SOS" (merah) atau "PENGADUAN" (navy muda).
class KindTag extends StatelessWidget {
  const KindTag({super.key, required this.sos, this.short = false});
  final bool sos, short;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: sos ? PK.red : PK.navySoft, borderRadius: BorderRadius.circular(6)),
    child: Text(
      sos ? 'SOS' : (short ? 'ADUAN' : 'PENGADUAN'),
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: sos ? Colors.white : PK.navy),
    ),
  );
}

/// Pil status mockup: Darurat/Baru (merah), Diproses (kuning), Selesai (hijau), Tidak valid/Dibatalkan (abu).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, required this.sos});
  final PkStatus status;
  final bool sos;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      PkStatus.baru => (sos ? 'Darurat' : 'Baru', const Color(0xFFFEE4E2), PK.redDark),
      PkStatus.diterima || PkStatus.diverifikasi || PkStatus.ditangani => ('Diproses', const Color(0xFFFEF0C7), const Color(0xFFB54708)),
      PkStatus.selesai => ('Selesai', const Color(0xFFD1FADF), PK.greenDark),
      PkStatus.tidakValid => ('Tidak valid', const Color(0xFFEEF2F8), PK.mute),
      PkStatus.dibatalkan => ('Dibatalkan', const Color(0xFFEEF2F8), PK.mute),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// Chip ekosistem: ikon lapis + pilar tebal + "· nama app".
class EcoChip extends StatelessWidget {
  const EcoChip({super.key, required this.label, this.app, this.onDark = false});
  final String label;
  final String? app;
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : PK.navy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: onDark ? Colors.white.withValues(alpha: 0.18) : PK.navySoft, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers_outlined, size: 13, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (app != null) TextSpan(text: ' · $app', style: TextStyle(fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75))),
                ],
              ),
              style: TextStyle(fontSize: 11.5, color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ gambar mini lampiran

/// Ubin lampiran: foto (gambar jaringan), video (gelap + ▶ + durasi), suara (mikrofon).
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, this.url, required this.kind, this.seconds, this.width = 58, this.height = 46});
  final String? url;
  final String kind; // image | video | audio
  final num? seconds;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final isAudio = kind == 'audio';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        color: isAudio ? const Color(0xFFEEF2F8) : const Color(0xFF3E4C63),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && kind == 'image')
              Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
            else if (kind == 'video')
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF7A8DA8), Color(0xFF2B3546)]),
                ),
              ),
            Center(
              child: Icon(
                switch (kind) {
                  'video' => Icons.play_arrow_rounded,
                  'audio' => Icons.mic_none_rounded,
                  _ => url == null ? Icons.image_outlined : null,
                },
                size: kind == 'video' ? 22 : 17,
                color: isAudio ? PK.navy : Colors.white,
              ),
            ),
            if (seconds != null && !isAudio)
              Positioned(
                right: 4,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                  child: Text(fmtClock(seconds!), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Deretan lampiran kartu: sampai 3 foto + 1 video + 1 suara.
class MediaThumbRow extends StatelessWidget {
  const MediaThumbRow({super.key, required this.r});
  final Report r;
  @override
  Widget build(BuildContext context) {
    final photos = r.thumbUrls.take(3).toList();
    final missing = (r.imageCount - photos.length).clamp(0, 3 - photos.length);
    final tiles = <Widget>[
      for (final u in photos) MediaThumb(url: u, kind: 'image'),
      for (var i = 0; i < missing; i++) const MediaThumb(kind: 'image'),
      if (r.videoCount > 0) MediaThumb(kind: 'video', seconds: r.videoSeconds),
      if (r.audioCount > 0) const MediaThumb(kind: 'audio'),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 6, runSpacing: 6, children: tiles),
    );
  }
}

/// "0:18" dari detik.
String fmtClock(num seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ------------------------------------------------------------------ kartu laporan

/// Kartu Tindak Lanjut: jenis + status + waktu, Berita, Ekosistem, Dari Siapa, No HP, Lokasi (+ jarak), lampiran,
/// tanggapan terakhir (atau "Belum ditanggapi").
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.r, this.here, this.onTap, this.showDate = true});
  final Report r;
  final ({double lat, double lng})? here;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final dist = r.distanceFrom(here);
    final last = r.lastResponse;
    final place = placeText(r);
    final who = [r.reporterName, ?r.sourcePlace].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.isDark ? context.hairline : const Color(0xFFE8EDF5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    KindTag(sos: r.isSos),
                    const SizedBox(width: 6),
                    StatusPill(status: r.status, sos: r.isSos),
                    const SizedBox(width: 6),
                    const Spacer(),
                    Icon(Icons.schedule_rounded, size: 13, color: context.ink2),
                    const SizedBox(width: 4),
                    Flexible(
                      flex: 100,
                      child: Text(
                        showDate ? '${fmtTime(r.createdAt)} · ${fmtDayMonth(r.createdAt)}' : fmtTime(r.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(r.headline, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.3, color: context.ink)),
                const SizedBox(height: 7),
                if (r.hasEcosystem) ...[EcoChip(label: r.ecosystemLabel, app: r.ecosystemApp), const SizedBox(height: 4)],
                _Kv(icon: Icons.person_outline_rounded, child: Text(who)),
                if (r.reporterPhone != null)
                  _Kv(
                    icon: Icons.phone_outlined,
                    child: Text(fmtPhone(r.reporterPhone!), style: TextStyle(fontWeight: FontWeight.w700, color: context.brand)),
                  ),
                if (r.handlerName != null && r.status != PkStatus.baru)
                  _Kv(
                    icon: Icons.verified_user_outlined,
                    child: Text(
                      r.handlerIsMe ? 'Ditangani oleh Anda' : 'Ditangani oleh ${officerName(r.handlerName)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: r.handlerIsMe ? PK.greenDark : context.ink),
                    ),
                  ),
                if (place.isNotEmpty || dist != null)
                  _Kv(
                    icon: Icons.location_on_outlined,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: place.isEmpty ? 'Lokasi GPS' : place),
                          if (dist != null) TextSpan(text: ' · $dist', style: TextStyle(color: context.ink2)),
                        ],
                      ),
                    ),
                  ),
                MediaThumbRow(r: r),
                const SizedBox(height: 12),
                const _Dashed(),
                const SizedBox(height: 10),
                if (last != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.assignment_turned_in_outlined, size: 16, color: context.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${officerName(last['officer'] as String?)}, ${fmtTime(DateTime.parse(last['created_at'] as String).toLocal())}: ',
                                style: TextStyle(fontWeight: FontWeight.w700, color: context.brand),
                              ),
                              TextSpan(text: responseText(last)),
                            ],
                          ),
                          style: TextStyle(fontSize: 12, height: 1.4, color: context.ink),
                        ),
                      ),
                    ],
                  )
                else if (r.status == PkStatus.baru)
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: context.dangerText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Belum ditanggapi', style: TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: ' · menunggu ${waitText(r.createdAt)}'),
                            ],
                          ),
                          style: TextStyle(fontSize: 12, color: context.dangerText),
                        ),
                      ),
                    ],
                  )
                else
                  Text('Belum ada catatan tindak lanjut', style: TextStyle(fontSize: 12, color: context.ink2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alamat kejadian + kelurahan, tanpa mengulang kelurahan bila alamat sudah memuatnya.
String placeText(Report r) {
  final base = r.locationText ?? r.sourcePlace;
  final kel = r.kelurahan;
  return [?base, if (kel != null && !(base ?? '').toLowerCase().contains('kel.')) 'Kel. ${kel.name}'].join(', ');
}

/// "Bripka Andi Saputra (Unit R2-07)" → "Bripka Andi Saputra".
String officerName(String? s) => (s ?? 'Petugas').replaceFirst(RegExp(r'\s*\(.*\)$'), '');

const _actionText = {
  'terima': 'Laporan diterima.',
  'hubungi': 'Menghubungi pelapor.',
  'verifikasi': 'Laporan diverifikasi.',
  'tangani': 'Sedang ditangani.',
  'selesai': 'Selesai ditangani.',
  'tidak_valid': 'Dinyatakan tidak valid.',
  'catatan': 'Catatan.',
};

/// Isi kolom Tindak Lanjut: catatan petugas, atau nama aksinya bila tanpa catatan.
String responseText(Map last) {
  final note = last['note'] as String?;
  if (note != null && note.isNotEmpty) return note;
  return _actionText[last['action']] ?? 'Ditanggapi.';
}

/// "2 mnt", "1 jam 5 mnt".
String waitText(DateTime since) {
  final d = DateTime.now().difference(since);
  if (d.inMinutes < 1) return '< 1 mnt';
  if (d.inMinutes < 60) return '${d.inMinutes} mnt';
  if (d.inHours < 24) return '${d.inHours} jam ${d.inMinutes % 60} mnt';
  return '${d.inDays} hari';
}

class _Kv extends StatelessWidget {
  const _Kv({required this.icon, required this.child});
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12.5, height: 1.35, color: context.ink),
            child: child,
          ),
        ),
      ],
    ),
  );
}

class _Dashed extends StatelessWidget {
  const _Dashed();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Row(
      children: List.generate(
        (c.maxWidth / 7).floor(),
        (_) => Container(width: 4, height: 1, margin: const EdgeInsets.only(right: 3), color: context.hairline),
      ),
    ),
  );
}

// ------------------------------------------------------------------ panel & grafik kecil

/// Panel putih radius 18 (kartu analitik / info).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(15), this.margin = const EdgeInsets.only(top: 10), this.border = false});
  final Widget child;
  final EdgeInsets padding, margin;
  final bool border;
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.surface,
      borderRadius: BorderRadius.circular(18),
      border: border ? Border.all(color: context.isDark ? context.hairline : const Color(0xFFE8EDF5)) : null,
    ),
    child: child,
  );
}

/// Judul panel + keterangan kecil di kanan.
class PanelTitle extends StatelessWidget {
  const PanelTitle(this.title, {super.key, this.hint, this.trailing});
  final String title;
  final String? hint;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: context.ink)),
      ),
      ?trailing,
      if (hint != null) Text(hint!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink2)),
    ],
  );
}

/// Judul bagian di luar panel ("Tindak Lanjut Terbaru", "Lampiran").
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.ink)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Bar mendatar (lintasan abu + isi berwarna), [value] 0..1.
class Track extends StatelessWidget {
  const Track({super.key, required this.value, this.color = PK.navy, this.height = 8, this.marker});
  final double value;
  final Color color;
  final double height;

  /// Garis target (0..1), mis. target 8 menit.
  final double? marker;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height + (marker != null ? 8 : 0),
    child: LayoutBuilder(
      builder: (context, c) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(color: context.isDark ? context.hairline : const Color(0xFFEEF2F8), borderRadius: BorderRadius.circular(height / 2)),
          ),
          Container(
            width: c.maxWidth * value.clamp(0, 1),
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
          ),
          if (marker != null)
            Positioned(
              left: c.maxWidth * marker!.clamp(0, 1) - 1,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: PK.red),
            ),
        ],
      ),
    ),
  );
}

/// Kotak saran kuning dengan ikon bohlam.
class InsightBox extends StatelessWidget {
  const InsightBox({super.key, required this.lead, required this.text});
  final String lead, text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.isDark ? const Color(0x22D4A82A) : const Color(0xFFFFF8E6),
      border: Border.all(color: context.isDark ? const Color(0x55D4A82A) : const Color(0xFFF4E2A8)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.lightbulb_outline_rounded, size: 18, color: Color(0xFFB98A0E)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: lead, style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' $text'),
              ],
            ),
            style: TextStyle(fontSize: 12.5, height: 1.45, color: context.isDark ? const Color(0xFFF5E3B0) : const Color(0xFF5C460B)),
          ),
        ),
      ],
    ),
  );
}

/// Sakelar kartu/tabel.
class ViewToggle extends StatelessWidget {
  const ViewToggle({super.key, required this.table, required this.onChanged, this.onDark = false});
  final bool table;
  final ValueChanged<bool> onChanged;
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    Widget seg(bool isTable, IconData icon, String tip) {
      final on = table == isTable;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(isTable),
          child: Container(
            width: 34,
            height: 28,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: on ? const [BoxShadow(color: Color(0x1F0F172A), blurRadius: 3, offset: Offset(0, 1))] : null,
            ),
            child: Icon(icon, size: 17, color: on ? PK.navy : (onDark ? PK.headerMute : PK.mute)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.12) : (context.isDark ? context.hairline : const Color(0xFFE3E9F3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(false, Icons.view_agenda_outlined, 'Tampilan kartu'), seg(true, Icons.table_chart_outlined, 'Tampilan tabel')],
      ),
    );
  }
}

/// Chip filter bulat: terpilih navy, lainnya putih bergaris; [count] tampil sebagai lencana kecil.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, this.count, required this.selected, required this.onTap, this.dashed = false});
  final String label;
  final int? count;
  final bool selected, dashed;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final fg = selected ? (dashed ? PK.navy : Colors.white) : context.ink;
    final bg = selected ? (dashed ? PK.navySoft : PK.navy) : (dashed ? Colors.transparent : context.surface);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? (dashed ? PK.blueTrack : PK.navy) : context.hairline),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: dashed && !selected ? FontWeight.w600 : FontWeight.w700, color: fg)),
                if (count != null) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFEEF2F8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : PK.text2)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ikon per pilar ekosistem.
IconData ecosystemIcon(String? source) => switch (source) {
  'umkm' => Icons.storefront_outlined,
  'warga' => Icons.holiday_village_outlined,
  'sekolah' => Icons.school_outlined,
  'kantor' => Icons.apartment_outlined,
  'komunitas' => Icons.groups_outlined,
  _ => Icons.layers_outlined,
};

/// "6,4" dari detik → menit dengan 1 desimal koma.
String minutes1(num? seconds) => seconds == null ? '–' : (seconds / 60).toStringAsFixed(1).replaceAll('.', ',');
