import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Dialog konfirmasi: ikon dalam kotak merah muda, judul tebal, isi di tengah, tombol Batal (abu) + aksi (merah).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Batal',
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      final accent = danger ? PK.red : PK.navy;
      return Dialog(
        backgroundColor: context.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: context.isDark ? 0.22 : 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: context.isDark && danger ? PK.redSoft : accent, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: t.titleLarge?.copyWith(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: context.ink2),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.isDark ? PK.darkLine : const Color(0xFFEEF0F4),
                          foregroundColor: context.ink,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PK.rButton)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        child: Text(cancelLabel),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PK.rButton)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok == true;
}
