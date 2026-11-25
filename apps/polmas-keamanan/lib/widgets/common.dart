import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';

// ---------------------------------------------------------------- tombol & kolom isian

/// Tombol utama: tinggi 52, lebar penuh, merah atau navy, teks putih 16 semibold, spinner saat memuat.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.loading = false, this.color, this.icon, this.trailingIcon, this.semanticsLabel});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;
  final IconData? icon;

  /// Ikon di kanan teks, mis. panah "Lanjut →".
  final IconData? trailingIcon;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (context.isDark ? const Color(0xFF2B4FA8) : PK.navy);
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            disabledBackgroundColor: bg.withValues(alpha: loading ? 0.85 : 0.4),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PK.rButton)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: loading
                ? const SizedBox(
                    key: ValueKey('l'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Row(
                    key: const ValueKey('t'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                      if (trailingIcon != null) ...[const SizedBox(width: 10), Icon(trailingIcon, size: 22)],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Kolom isian: label di atas, ikon di kiri, tinggi 52, fokus navy 2 px, salah merah + pesan 13.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.prefixText,
    this.hint,
    this.error,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.onSubmitted,
    this.autofillHints,
    this.textInputAction,
  });
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final String? prefixText, hint, error;
  final bool obscure, autofocus;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: context.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.3),
          decoration: InputDecoration(
            prefixIcon: icon == null ? null : Icon(icon, color: error != null ? context.danger : context.ink2),
            prefixText: prefixText,
            prefixStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: context.ink),
            hintText: hint,
            errorText: error,
            errorMaxLines: 3,
            suffixIcon: suffix,
            constraints: const BoxConstraints(minHeight: 52),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- animasi

/// Getar salah isian: 320 ms linear, tiga ayunan ±6 px. Panggil `key.currentState?.shake()`.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.child});
  final Widget child;
  @override
  State<Shake> createState() => ShakeState();
}

class ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: PK.shake);
  void shake() {
    HapticFeedback.mediumImpact();
    if (context.reduceMotion) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(offset: Offset(math.sin(_c.value * math.pi * 6) * 6 * (1 - _c.value * 0.3), 0), child: child),
    child: widget.child,
  );
}

/// Kartu muncul: 300 ms, jeda 60 ms per indeks, naik 12 px sambil memudar. "Kurangi gerakan" = langsung tampil.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: PK.cardIn);
  @override
  void initState() {
    super.initState();
    Future.delayed(PK.cardStagger * math.min(widget.index, 8), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, 12 * (1 - a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Angka naik hitung dari 0 dalam 800 ms ease-out.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.style, this.suffix = ''});
  final num value;
  final TextStyle? style;
  final String suffix;
  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return Text('${fmtNumber(value)}$suffix', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: PK.countUp,
      curve: Curves.easeOut,
      builder: (_, v, _) => Text('${value is int ? fmtNumber(v.round()) : v.toStringAsFixed(1).replaceAll('.', ',')}$suffix', style: style),
    );
  }
}

// ---------------------------------------------------------------- Merah Putih

/// Pita merah putih di tepi atas (header dashboard, splash, login).
class MerahPutihRibbon extends StatelessWidget {
  const MerahPutihRibbon({super.key, this.height = 6});
  final double height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(child: Container(color: PK.red)),
          Expanded(child: Container(color: Colors.white)),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- lencana & kartu

/// Lencana status (pil penuh): Darurat merah, Diproses emas, Selesai hijau; selalu ikon + teks, bukan warna saja.
/// [detail] = label rinci (Diterima/Diverifikasi/Ditangani) alih-alih kelompok "Diproses".
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, required this.sos, this.compact = false, this.detail = false});
  final PkStatus status;
  final bool sos;
  final bool compact;
  final bool detail;
  @override
  Widget build(BuildContext context) {
    final processing = const {PkStatus.diterima, PkStatus.diverifikasi, PkStatus.ditangani}.contains(status);
    final st = statusStyle(status, sos: sos);
    final label = processing && !detail ? 'Diproses' : st.label;
    final (Color bg, Color fg, IconData icon) = switch (st.color) {
      PK.red => (PK.red, Colors.white, Icons.notifications_active_rounded),
      PK.gold => (const Color(0xFFF7C948), const Color(0xFF4A3400), Icons.schedule_rounded),
      PK.green => (PK.green, Colors.white, Icons.check_rounded),
      PK.navy => (context.brand, context.isDark ? PK.darkBg : Colors.white, Icons.fiber_new_rounded),
      _ => (context.isDark ? PK.darkLine : const Color(0xFFE2E8F0), context.ink2, st.icon),
    };
    return Semantics(
      label: 'Status $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 14 : 16, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? context.surface,
      borderRadius: BorderRadius.circular(PK.rCard),
      boxShadow: context.isDark ? null : PK.cardShadow,
      border: context.isDark ? Border.all(color: context.hairline) : null,
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(PK.rCard),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Kartu insiden. [thumbnail] = gambar mini di kiri (Beranda); tanpa itu = bilah warna status 4 px (Riwayat).
/// Isi: judul, "± jarak · waktu relatif", lencana status, panah.
class IncidentCard extends StatelessWidget {
  const IncidentCard({super.key, required this.report, this.onTap, this.thumbnail = false, this.from});
  final Report report;
  final VoidCallback? onTap;
  final bool thumbnail;

  /// Titik pengguna untuk jarak (lokasi konfirmasi wilayah).
  final ({double lat, double lng})? from;
  @override
  Widget build(BuildContext context) {
    final r = report;
    final st = statusStyle(r.group, sos: r.isSos);
    final bar = st.color == PK.red
        ? context.danger
        : st.color == PK.navy
        ? context.brand
        : st.color;
    final t = Theme.of(context).textTheme;
    final dist = r.distanceFrom(from);
    final meta = [?dist, fmtRelative(r.createdAt)].join(' · ');
    return Semantics(
      button: true,
      label: '${r.isSos ? 'SOS' : 'Laporan'} ${r.headline}, ${r.placeLine}, $meta, status ${st.label}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(PK.rCard),
          boxShadow: context.isDark ? null : PK.cardShadow,
          border: context.isDark ? Border.all(color: context.hairline) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!thumbnail) Container(width: 4, color: bar),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(thumbnail ? 10 : 14, 10, 6, 10),
                      child: Row(
                        children: [
                          if (thumbnail) ...[_Thumb(r: r), const SizedBox(width: 12)],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  r.headline,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(dist != null ? Icons.near_me_rounded : Icons.schedule_rounded, size: 13, color: context.ink2),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    StatusBadge(status: r.group, sos: r.isSos, compact: true),
                                    const SizedBox(width: 8),
                                    if (r.videoCount > 0) _Mini(icon: Icons.videocam_rounded, text: '${r.videoCount}'),
                                    if (r.imageCount > 0) _Mini(icon: Icons.photo_rounded, text: '${r.imageCount}'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: context.ink2),
                        ],
                      ),
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.r});
  final Report r;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: r.isSos ? const [Color(0xFFE53935), PK.redDark] : const [Color(0xFF3B5BA9), PK.navy],
        ),
      ),
      child: Icon(r.isSos ? Icons.notifications_active_rounded : categoryIcon(r.category), color: Colors.white, size: 30),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 76,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (r.thumbUrl != null) Image.network(r.thumbUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback) else fallback,
            if (r.videoCount > 0 && r.thumbUrl == null) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 26)),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.ink2),
        const SizedBox(width: 2),
        Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.ink2),
        ),
      ],
    ),
  );
}

/// Kisi 2 kolom untuk kartu angka. Tinggi tiap baris mengikuti isi tertinggi (bukan rasio tetap), jadi tidak meluap
/// saat ukuran huruf perangkat diperbesar.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.gap = 10});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) SizedBox(height: gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              SizedBox(width: gap),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Kartu angka berwarna lembut: ikon + label kecil di atas, angka besar naik hitung, opsional perubahan (↑/↓ %).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.delta,
    this.lowerIsBetter = false,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// Persen perubahan dari periode sebelumnya (null = tidak ditampilkan).
  final int? delta;
  final bool lowerIsBetter;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = delta;
    final good = d == null || d == 0 ? null : (lowerIsBetter ? d < 0 : d > 0);
    final dc = good == null ? context.ink2 : (good ? PK.green : context.danger);
    return Semantics(
      label: '$label: $value${d != null ? ', ${d >= 0 ? 'naik' : 'turun'} ${d.abs()} persen' : ''}',
      excludeSemantics: true,
      button: onTap != null,
      child: Material(
        color: context.isDark ? color.withValues(alpha: 0.16) : Color.alphaBlend(color.withValues(alpha: 0.10), Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PK.rCard),
          side: BorderSide(color: color.withValues(alpha: context.isDark ? 0.35 : 0.22)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(PK.rCard),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        style: t.bodySmall?.copyWith(color: context.ink, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CountUp(
                            value: value,
                            style: t.displaySmall?.copyWith(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800),
                          ),
                          if (d != null) ...[
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${d > 0
                                    ? '↑'
                                    : d < 0
                                    ? '↓'
                                    : '→'} ${d > 0 ? '+' : ''}$d%',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: dc),
                              ),
                            ),
                          ],
                        ],
                      ),
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
}

// ---------------------------------------------------------------- keadaan kosong / galat / toast

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: context.brand.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 34, color: context.brand),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.ink2),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.wifi_off_rounded,
    title: 'Gagal memuat',
    body: message,
    action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Coba lagi')),
  );
}

/// Toast muncul dari atas selama 3 detik (bisa ditutup ×); sukses hijau muda, galat merah muda.
void showToast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  var removed = false;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      error: error,
      onDone: () {
        if (removed) return;
        removed = true;
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
  SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.error, required this.onDone});
  final String message;
  final bool error;
  final VoidCallback onDone;
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(seconds: 3), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: a,
        builder: (_, child) => Opacity(
          opacity: a.value,
          child: Transform.translate(offset: Offset(0, -24 * (1 - a.value)), child: child),
        ),
        child: Material(
          color: widget.error ? const Color(0xFFFDECEC) : const Color(0xFFE8F7EE),
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
            child: Row(
              children: [
                Icon(widget.error ? Icons.error_rounded : Icons.check_circle_rounded, color: widget.error ? PK.red : PK.green, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(color: widget.error ? PK.redDark : const Color(0xFF0F5132), fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: _close,
                  icon: Icon(Icons.close_rounded, color: widget.error ? PK.redDark : const Color(0xFF0F5132)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pita "DEMO": data fase 1 fiktif harus ditandai jelas.
class DemoTag extends StatelessWidget {
  const DemoTag({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mode demo, data fiktif',
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: PK.gold, borderRadius: BorderRadius.circular(6)),
      child: const Text(
        'DEMO',
        style: TextStyle(color: PK.text, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
      ),
    ),
  );
}

/// Judul bagian kecil di daftar.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: context.ink2)),
        ),
        ?trailing,
      ],
    ),
  );
}
