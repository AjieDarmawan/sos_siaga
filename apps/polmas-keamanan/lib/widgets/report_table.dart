import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../screens/incident_screen.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Kolom laporan yang ditampilkan di Beranda (urutan & ikon sama untuk tampilan kartu dan tabel).
enum ReportField {
  berita('Berita', Icons.article_outlined),
  noHp('No HP', Icons.phone_outlined),
  ekosistem('Ekosistem', Icons.layers_outlined),
  dariSiapa('Dari Siapa', Icons.person_outline_rounded),
  media('Foto/Video', Icons.perm_media_outlined),
  lokasi('Lokasi', Icons.location_on_outlined),
  waktu('Waktu', Icons.calendar_today_outlined),
  status('Status', Icons.check_circle_outline_rounded),
  tindakLanjut('Tindak Lanjut', Icons.assignment_turned_in_outlined);

  const ReportField(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _actionLabel = {
  'terima': 'Diterima',
  'hubungi': 'Menghubungi pelapor',
  'verifikasi': 'Diverifikasi',
  'tangani': 'Ditangani',
  'selesai': 'Selesai ditangani',
  'tidak_valid': 'Dinyatakan tidak valid',
  'catatan': 'Catatan petugas',
};

/// Isi kolom "Tindak Lanjut": tanggapan terakhir (aksi · petugas) + catatan, atau "Belum ditanggapi".
({String title, String? note, bool pending}) followUp(Report r) {
  final x = r.lastResponse;
  if (x == null) {
    final closed = const {PkStatus.selesai, PkStatus.tidakValid, PkStatus.dibatalkan}.contains(r.status);
    return (title: closed ? 'Ditutup tanpa catatan' : 'Belum ditanggapi', note: null, pending: !closed);
  }
  final officer = (x['officer'] as String?)?.split(' (').first;
  return (
    title: [_actionLabel[x['action']] ?? 'Ditanggapi', ?officer].join(' · '),
    note: (x['note'] as String?)?.isNotEmpty == true ? x['note'] as String : null,
    pending: false,
  );
}

String _ecosystem(Report r) {
  final app = r.raw['app_name'] as String?;
  return app == null || app == r.sourceLabel ? r.sourceLabel : '${r.sourceLabel} · $app';
}

Future<void> _call(String phone) => launchUrl(Uri(scheme: 'tel', path: '+${phone.replaceAll(RegExp(r'[^0-9]'), '')}'));

Future<void> _openMap(Report r) async {
  final l = r.location;
  if (l != null) {
    await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${l.lat},${l.lng}'), mode: LaunchMode.externalApplication);
  }
}

// ---------------------------------------------------------------- tampilan kartu

/// Kartu laporan lengkap: judul (Berita) + status di atas, lalu No HP, Ekosistem, Dari Siapa, Lokasi, Waktu, Video,
/// dan pita Tindak Lanjut di bawah. Ketuk kartu → detail; ketuk No HP → telepon; ketuk Lokasi → peta.
class ReportFieldsCard extends StatelessWidget {
  const ReportFieldsCard({super.key, required this.report, this.from});
  final Report report;
  final ({double lat, double lng})? from;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final t = Theme.of(context).textTheme;
    final fu = followUp(r);
    final dist = r.distanceFrom(from);
    final st = statusStyle(r.group, sos: r.isSos);
    final bar = st.color == PK.red
        ? context.danger
        : st.color == PK.navy
        ? context.brand
        : st.color;
    return Semantics(
      container: true,
      label: '${r.isSos ? 'SOS' : 'Laporan'}: ${r.headline}. Status ${st.label}. ${fu.title}',
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(PK.rCard),
          boxShadow: context.isDark ? null : PK.cardShadow,
          border: Border(left: BorderSide(color: bar, width: 4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => openIncident(context, r.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Berita + Status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(ReportField.berita.icon, size: 20, color: context.ink2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (r.message != null && r.message != r.headline)
                              Text(
                                r.message!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall?.copyWith(color: context.ink2),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(status: r.group, sos: r.isSos, compact: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: context.hairline),
                  const SizedBox(height: 8),
                  // isian 2 kolom
                  LayoutBuilder(
                    builder: (context, cs) {
                      final half = (cs.maxWidth - 12) / 2;
                      Widget cell(ReportField f, String value, {VoidCallback? onTap, Color? color, bool muted = false}) => SizedBox(
                        width: half,
                        child: _Cell(field: f, value: value, onTap: onTap, color: color, muted: muted),
                      );
                      return Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          cell(
                            ReportField.noHp,
                            r.reporterPhone != null ? fmtPhone(r.reporterPhone!) : 'Disamarkan',
                            onTap: r.reporterPhone != null ? () => _call(r.reporterPhone!) : null,
                            color: r.reporterPhone != null ? PK.green : null,
                            muted: r.reporterPhone == null,
                          ),
                          cell(ReportField.dariSiapa, r.isMine ? '${r.reporterName} (Anda)' : r.reporterName),
                          cell(ReportField.ekosistem, _ecosystem(r)),
                          cell(ReportField.waktu, fmtDayTime(r.createdAt)),
                          cell(
                            ReportField.lokasi,
                            [if (r.placeLine.isNotEmpty) r.placeLine else 'Belum diketahui', ?dist].join(' · '),
                            onTap: r.location != null ? () => _openMap(r) : null,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(ReportField.media.icon, size: 16, color: context.ink2),
                      const SizedBox(width: 6),
                      Text(ReportField.media.label, style: t.labelSmall?.copyWith(color: context.ink2, fontSize: 12)),
                      const SizedBox(width: 10),
                      Expanded(child: MediaThumbs(report: r, size: 48)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tindak Lanjut
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: (fu.pending ? context.danger : PK.green).withValues(alpha: context.isDark ? 0.16 : 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(ReportField.tindakLanjut.icon, size: 18, color: fu.pending ? context.dangerText : PK.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fu.title,
                                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: fu.pending ? context.dangerText : context.ink),
                              ),
                              if (fu.note != null) Text(fu.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.ink2, size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.field, required this.value, this.onTap, this.color, this.muted = false});
  final ReportField field;
  final String value;
  final VoidCallback? onTap;
  final Color? color;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(field.icon, size: 16, color: color ?? context.ink2),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label, style: t.labelSmall?.copyWith(color: context.ink2, fontSize: 12)),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted ? context.ink2 : (color ?? context.ink),
                    decoration: onTap != null ? TextDecoration.underline : null,
                    decorationColor: color ?? context.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: '${field.label}: $value',
      button: onTap != null,
      excludeSemantics: true,
      child: onTap == null ? body : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: body),
    );
  }
}

// ---------------------------------------------------------------- tampilan tabel

/// Tabel laporan (geser ke samping): header navy berikon + label putih, baris bergaris tipis. Ketuk baris → detail.
class ReportTable extends StatelessWidget {
  const ReportTable({super.key, required this.reports, this.from});
  final List<Report> reports;
  final ({double lat, double lng})? from;

  static const _w = {
    ReportField.berita: 220.0,
    ReportField.noHp: 140.0,
    ReportField.ekosistem: 170.0,
    ReportField.dariSiapa: 150.0,
    ReportField.media: 150.0,
    ReportField.lokasi: 190.0,
    ReportField.waktu: 150.0,
    ReportField.status: 150.0,
    ReportField.tindakLanjut: 220.0,
  };

  @override
  Widget build(BuildContext context) {
    final line = context.isDark ? PK.darkLine : const Color(0xFFCBD2DC);
    final head = context.isDark ? const Color(0xFF1B2A4E) : const Color(0xFF1E2F55);
    final t = Theme.of(context).textTheme;
    final total = _w.values.fold<double>(0, (a, b) => a + b);

    Widget cellBox(ReportField f, Widget child, {Color? bg}) => Container(
      width: _w[f],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: f == ReportField.tindakLanjut ? BorderSide.none : BorderSide(color: bg == null ? line : Colors.white24)),
      ),
      child: child,
    );

    Widget row(Report r, int i) {
      final fu = followUp(r);
      final dist = r.distanceFrom(from);
      Text txt(String s, {Color? c, FontWeight w = FontWeight.w500, int lines = 2}) => Text(
        s,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: t.bodySmall?.copyWith(fontSize: 13, color: c ?? context.ink, fontWeight: w),
      );
      return Semantics(
        button: true,
        label: '${r.headline}, ${r.reporterName}, ${fmtDayTime(r.createdAt)}, ${fu.title}',
        child: InkWell(
          onTap: () => openIncident(context, r.id),
          child: Container(
            decoration: BoxDecoration(
              color: i.isOdd ? (context.isDark ? PK.darkBg : const Color(0xFFF8FAFC)) : context.surface,
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cellBox(
                    ReportField.berita,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        txt(r.headline, w: FontWeight.w800, lines: 1),
                        if (r.message != null) txt(r.message!, c: context.ink2),
                      ],
                    ),
                  ),
                  cellBox(
                    ReportField.noHp,
                    r.reporterPhone != null
                        ? InkWell(
                            onTap: () => _call(r.reporterPhone!),
                            child: Row(
                              children: [
                                const Icon(Icons.call_rounded, size: 15, color: PK.green),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: txt(fmtPhone(r.reporterPhone!), c: PK.green, w: FontWeight.w700, lines: 1),
                                ),
                              ],
                            ),
                          )
                        : txt('Disamarkan', c: context.ink2),
                  ),
                  cellBox(ReportField.ekosistem, txt(_ecosystem(r))),
                  cellBox(ReportField.dariSiapa, txt(r.isMine ? '${r.reporterName} (Anda)' : r.reporterName, w: FontWeight.w600)),
                  cellBox(ReportField.media, MediaThumbs(report: r, size: 40)),
                  cellBox(
                    ReportField.lokasi,
                    InkWell(
                      onTap: r.location != null ? () => _openMap(r) : null,
                      child: txt([if (r.placeLine.isNotEmpty) r.placeLine else 'Belum diketahui', ?dist].join(' · ')),
                    ),
                  ),
                  cellBox(ReportField.waktu, txt(fmtDayTime(r.createdAt))),
                  cellBox(
                    ReportField.status,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(status: r.status, sos: r.isSos, compact: true, detail: true),
                    ),
                  ),
                  cellBox(
                    ReportField.tindakLanjut,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        txt(fu.title, w: FontWeight.w700, c: fu.pending ? context.dangerText : null, lines: 1),
                        if (fu.note != null) txt(fu.note!, c: context.ink2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(PK.rCard),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(PK.rCard),
          color: context.surface,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: total,
            child: Column(
              children: [
                // header navy berikon
                Container(
                  color: head,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final f in ReportField.values)
                          cellBox(
                            f,
                            Semantics(
                              header: true,
                              child: Row(
                                children: [
                                  Icon(f.icon, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      f.label,
                                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            bg: head,
                          ),
                      ],
                    ),
                  ),
                ),
                for (final (i, r) in reports.indexed) row(r, i),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gambar mini bukti: foto pertama (bila ada) + ringkasan "2 foto · 1 video"; tanpa bukti = "Belum ada".
class MediaThumbs extends StatelessWidget {
  const MediaThumbs({super.key, required this.report, this.size = 44});
  final Report report;
  final double size;
  @override
  Widget build(BuildContext context) {
    final r = report;
    final parts = [if (r.imageCount > 0) '${r.imageCount} foto', if (r.videoCount > 0) '${r.videoCount} video'];
    if (parts.isEmpty) {
      return Text('Belum ada', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink2, fontSize: 13));
    }
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (r.thumbUrl != null)
              Image.network(
                r.thumbUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1F2937)),
              )
            else
              const ColoredBox(color: Color(0xFF1F2937)),
            if (r.thumbUrl == null || r.videoCount > 0)
              Center(
                child: Icon(r.videoCount > 0 ? Icons.play_circle_fill_rounded : Icons.photo_rounded, color: Colors.white, size: size * 0.5),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      label: 'Bukti: ${parts.join(', ')}',
      excludeSemantics: true,
      child: Row(
        children: [
          tile,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              parts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink),
            ),
          ),
        ],
      ),
    );
  }
}
