import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'push.dart';
import 'models.dart';

/// State global: sesi, profil, tema, polling SOS masuk & notifikasi.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState() {
    api.onUnauthorized = _relogin;
    WidgetsBinding.instance.addObserver(this);
  }

  final api = Api();
  static const _secure = FlutterSecureStorage();

  Me? me;
  int unread = 0;
  ThemeMode themeMode = ThemeMode.system;

  /// Bunyi sirene & getar saat SOS masuk. Layar panggilan tetap muncul walau dimatikan (SOS prioritas tertinggi).
  bool notifSound = true;

  /// "Kurangi gerakan" di dalam app (selain pengaturan perangkat).
  bool reduceMotion = false;
  String? savedPhone;
  bool hasSavedPassword = false;

  /// Naik setiap ada perubahan data (tanggapan, SOS baru) supaya layar yang terbuka memuat ulang.
  int dataVersion = 0;
  bool online = true;

  /// Dipanggil saat ada SOS masuk baru (layar panggilan penuh). Dipasang oleh [PolmasApp].
  void Function(Report call)? onIncomingCall;
  final _ringing = <String>{};
  Timer? _poll;
  bool _resumed = true;

  bool get loggedIn => me != null && api.token != null;

  /// Posisi HP penerima (hanya untuk jarak "± 350 m" ke lokasi SOS). Wilayah/peran TIDAK dari GPS, tapi dari Nomor Darurat.
  ({double lat, double lng})? devicePos;
  ({double lat, double lng})? get here => devicePos ?? me?.areaLocation;

  /// Baca lokasi sekali bila izin sudah/diberikan; gagal = jarak tidak ditampilkan.
  Future<void> refreshPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final p =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
          );
      devicePos = (lat: p.latitude, lng: p.longitude);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.firstWhere((m) => m.name == prefs.getString('theme'), orElse: () => ThemeMode.system);
    notifSound = prefs.getBool('notif_sound') ?? true;
    reduceMotion = prefs.getBool('reduce_motion') ?? false;
    try {
      savedPhone = await _secure.read(key: 'pk_phone');
      hasSavedPassword = (await _secure.read(key: 'pk_password')) != null;
    } catch (_) {
      // Keystore rusak setelah restore backup: anggap belum ada kredensial.
      savedPhone = null;
      hasSavedPassword = false;
    }
  }

  Future<String?> savedPassword() => _secure.read(key: 'pk_password');

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('theme', m.name);
  }

  Future<void> setNotifSound(bool v) async {
    notifSound = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('notif_sound', v);
  }

  Future<void> setReduceMotion(bool v) async {
    reduceMotion = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('reduce_motion', v);
  }

  Future<void> updateName(String name) async {
    me = Me(await api.patch('/me', {'name': name}) as Map);
    notifyListeners();
  }

  /// Langkah 1: nomor terdaftar bila ada di Nomor Darurat app sumber mana pun (atau dibuat admin).
  /// `has_password == false` → login pertama, pengguna membuat password.
  Future<PhoneCheck> checkPhone(String phone) async => PhoneCheck(await api.post('/auth/check', {'phone': phone}) as Map);

  Map<String, String> get _device => {'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'};

  Future<void> login(String phone, String password) async =>
      _onSession(await api.post('/auth/login', {'phone': phone, 'password': password, 'device': _device}) as Map, phone, password);

  /// Login pertama nomor dari Nomor Darurat: membuat akun + password.
  Future<void> setupAccount(String phone, String password) async =>
      _onSession(await api.post('/auth/setup', {'phone': phone, 'password': password, 'device': _device}) as Map, phone, password);

  Future<void> _onSession(Map r, String phone, String password) async {
    api.token = r['token'] as String;
    me = Me(r['me'] as Map);
    // Login cepat (FR-02): nomor & password disimpan terenkripsi di perangkat (Keystore/Keychain).
    await _secure.write(key: 'pk_phone', value: phone);
    await _secure.write(key: 'pk_password', value: password);
    savedPhone = phone;
    hasSavedPassword = true;
    _startPolling();
    unawaited(_registerDevice());
    notifyListeners();
  }

  Future<bool> _relogin() async {
    final phone = await _secure.read(key: 'pk_phone');
    final pw = await _secure.read(key: 'pk_password');
    if (phone == null || pw == null) return _expire();
    try {
      final r = await api.post('/auth/login', {'phone': phone, 'password': pw}) as Map;
      api.token = r['token'] as String;
      me = Me(r['me'] as Map);
      unawaited(_registerDevice());
      return true;
    } catch (_) {
      return _expire();
    }
  }

  bool _expire() {
    api.token = null;
    me = null;
    _poll?.cancel();
    notifyListeners();
    return false;
  }

  Future<void> refreshMe() async {
    me = Me(await api.get('/me') as Map);
    notifyListeners();
  }

  Future<void> confirmArea(Area a, {double? lat, double? lng}) async {
    me = Me(
      await api.put('/me/area', {
        'province': a.province!.toJson(),
        'regency': a.regency!.toJson(),
        'district': a.district!.toJson(),
        'village': a.village?.toJson(),
        'lat': lat,
        'lng': lng,
      }) as Map,
    );
    bump();
  }

  Future<void> switchRole(String roleId) async {
    me = Me(await api.post('/me/role', {'role_id': roleId}) as Map);
    _ringing.clear();
    bump();
  }

  String? _fcmToken;
  StreamSubscription<String>? _tokenSub;

  /// Daftarkan token FCM HP ini ke server supaya SOS yang memanggil nomor ini berbunyi walau app ditutup.
  Future<void> _registerDevice([String? token]) async {
    final t = token ?? await Push.token();
    if (t == null || !loggedIn) return;
    _fcmToken = t;
    _tokenSub ??= Push.tokenChanges.listen(_registerDevice);
    try {
      await api.post('/me/device', {'fcm_token': t, 'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'});
    } catch (_) {}
  }

  Future<void> logout() async {
    // HP ini berhenti menerima SOS untuk nomor ini.
    if (_fcmToken != null) {
      try {
        await api.post('/me/device/remove', {'fcm_token': _fcmToken});
      } catch (_) {}
    }
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    api.token = null;
    me = null;
    unread = 0;
    lastLogoutManual = true;
    _poll?.cancel();
    notifyListeners();
  }

  /// true = keluar lewat tombol Keluar (login menampilkan "Berhasil keluar"); false = sesi berakhir.
  bool lastLogoutManual = false;

  /// "Lupakan perangkat": hapus nomor & password tersimpan.
  Future<void> forgetDevice() async {
    await _secure.delete(key: 'pk_phone');
    await _secure.delete(key: 'pk_password');
    savedPhone = null;
    hasSavedPassword = false;
    notifyListeners();
  }

  void bump() {
    dataVersion++;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    await api.post('/notifications/read-all');
    unread = 0;
    notifyListeners();
  }

  // ------------------------------------------------------------ polling SOS masuk

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => pollNow());
    pollNow();
  }

  Future<void> pollNow() async {
    if (!loggedIn || !_resumed) return;
    try {
      final r = await api.get('/inbox') as Map;
      final wasOffline = !online;
      online = true;
      final u = (r['unread'] as num).toInt();
      var changed = u != unread || wasOffline;
      unread = u;
      for (final c in (r['calls'] as List)) {
        final rep = Report(c as Map);
        if (_ringing.add(rep.id)) {
          changed = true;
          dataVersion++;
          onIncomingCall?.call(rep);
          break; // satu layar panggilan sekaligus; sisanya muncul di polling berikut
        }
      }
      if (changed) notifyListeners();
    } on ApiException catch (e) {
      if (e.isNetwork && online) {
        online = false;
        notifyListeners();
      }
    }
  }

  /// Panggilan yang sudah dijawab boleh berdering lagi hanya bila server masih mengirimnya (mis. gagal simpan).
  void releaseCall(String id) => _ringing.remove(id);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) pollNow();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Akses [AppState] dari widget mana pun: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
