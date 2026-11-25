import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/app_state.dart';
import 'core/models.dart';
import 'screens/login_screen.dart';
import 'screens/sos_call_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id');
  final state = AppState();
  await state.init();
  runApp(PolmasApp(state: state));
}

final navigatorKey = GlobalKey<NavigatorState>();

class PolmasApp extends StatefulWidget {
  const PolmasApp({super.key, required this.state});
  final AppState state;
  @override
  State<PolmasApp> createState() => _PolmasAppState();
}

class _PolmasAppState extends State<PolmasApp> {
  bool _wasLoggedIn = false;
  String? _callOpen;

  @override
  void initState() {
    super.initState();
    widget.state.onIncomingCall = _showCall;
    widget.state.addListener(_onState);
  }

  /// SOS masuk: layar panggilan penuh di atas layar apa pun (prioritas tertinggi).
  void _showCall(Report r) {
    if (_callOpen != null) return;
    _callOpen = r.id;
    navigatorKey.currentState
        ?.push(
          PageRouteBuilder(
            opaque: true,
            fullscreenDialog: true,
            transitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (_, _, _) => SosCallScreen(report: r),
            transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          ),
        )
        .whenComplete(() => _callOpen = null);
  }

  /// Sesi habis & login cepat gagal → kembali ke login.
  void _onState() {
    final now = widget.state.loggedIn;
    if (_wasLoggedIn && !now) {
      final manual = widget.state.lastLogoutManual;
      widget.state.lastLogoutManual = false;
      navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen(justLoggedOut: manual)), (_) => false);
    }
    _wasLoggedIn = now;
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => MaterialApp(
          title: 'Polmas Keamanan',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: widget.state.themeMode,
          // Toggle "Kurangi gerakan" di Profil = sama dengan pengaturan perangkat (dibaca lewat context.reduceMotion).
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(disableAnimations: mq.disableAnimations || widget.state.reduceMotion),
              child: child!,
            );
          },
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
