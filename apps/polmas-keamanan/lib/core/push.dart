import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push FCM (project Firebase `siagasos-a61e9`). SOS yang memanggil nomor penerima dikirim server ke kanal Android
/// `polmas_sos` (sirene, prioritas tertinggi) sehingga tetap berbunyi saat app ditutup. Saat app terbuka, push hanya
/// memicu [onSos] (cek /inbox → layar panggilan penuh).
///
/// Tanpa konfigurasi Firebase (mis. iOS belum punya GoogleService-Info.plist) semua fungsi diam-diam nonaktif;
/// panggilan tetap muncul lewat polling saat app terbuka.
class Push {
  Push._();
  static bool _ready = false;
  static bool get ready => _ready;
  static final _tokenChanges = StreamController<String>.broadcast();

  /// Token baru (refresh) untuk didaftarkan ulang ke server.
  static Stream<String> get tokenChanges => _tokenChanges.stream;

  static Future<void> init({required void Function() onSos}) async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase tidak aktif: $e');
      return;
    }
    _ready = true;
    final m = FirebaseMessaging.instance;
    try {
      await m.requestPermission(alert: true, sound: true, badge: true);
    } catch (_) {}
    FirebaseMessaging.onMessage.listen((msg) {
      if (msg.data['type'] == 'sos') onSos();
    });
    // Ketuk notifikasi saat app di latar belakang / dibuka dari notifikasi.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => onSos());
    unawaited(
      m.getInitialMessage().then((msg) {
        if (msg != null) onSos();
      }),
    );
    // getToken/onTokenRefresh sengaja dipakai (deprecated di firebase_messaging 17): API baru register()/onRegistered
    // memberi Firebase Installation ID untuk "direct-send", sedangkan server mengirim via FCM HTTP v1 `message.token`
    // yang butuh token registrasi ini (apps/api/src/lib/fcm.ts).
    // ignore: deprecated_member_use
    m.onTokenRefresh.listen(_tokenChanges.add);
  }

  static Future<String?> token() async {
    if (!_ready) return null;
    try {
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Token FCM gagal: $e');
      return null;
    }
  }
}
