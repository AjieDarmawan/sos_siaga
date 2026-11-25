import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'area_screen.dart';

/// Login dua langkah (FR-01, FR-02): nomor telepon terdaftar (Nomor Darurat) → password, atau buat password pada
/// login pertama. Setelah keluar, nomor & password terisi otomatis dari perangkat (login cepat) dengan tautan
/// "Bukan saya?" dan "Lupakan perangkat ini".
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.justLoggedOut = false});

  /// Tampilkan toast "Berhasil keluar" saat layar dibuka.
  final bool justLoggedOut;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phoneShake = GlobalKey<ShakeState>();
  final _pwShake = GlobalKey<ShakeState>();
  int _step = 0;
  bool _loading = false;
  bool _obscure = true;
  bool _prefilled = false;

  /// Password berasal dari penyimpanan perangkat dan belum diubah → kotak info "Terisi otomatis".
  bool _autofilled = false;
  String? _error;
  String? _normalized;
  PhoneCheck? _check;

  /// Login pertama untuk nomor dari Nomor Darurat: buat password (tanpa OTP, sesuai PRD).
  bool get _firstTime => _check != null && !_check!.hasPassword;

  String get _digits => _phone.text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^(62|0)'), '');
  bool get _phoneValid => _digits.length >= 9 && _digits.startsWith('8');

  @override
  void initState() {
    super.initState();
    _phone.addListener(() => setState(() {}));
    _password.addListener(() {
      if (_autofilled && mounted) setState(() => _autofilled = false);
    });
    if (widget.justLoggedOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showToast(context, 'Berhasil keluar');
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final s = AppScope.read(context);
    if (s.savedPhone != null) {
      _phone.text = dashLocal(s.savedPhone!.startsWith('62') ? s.savedPhone!.substring(2) : s.savedPhone!);
      if (s.hasSavedPassword) {
        s.savedPassword().then((p) {
          if (!mounted || p == null) return;
          _password.text = p;
          setState(() => _autofilled = true);
        });
      }
    }
  }

  Future<void> _next() async {
    if (!_phoneValid) {
      setState(() => _error = 'Masukkan nomor HP yang benar, mis. 812-3456-7890.');
      _phoneShake.currentState?.shake();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _check = await AppScope.read(context).checkPhone('62$_digits');
      _normalized = _check!.phone;
      if (!mounted) return;
      setState(() {
        _step = 1;
        if (_firstTime) {
          _password.clear();
          _confirm.clear();
          _autofilled = false;
        }
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _phoneShake.currentState?.shake();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final err = _password.text.isEmpty
        ? 'Masukkan password.'
        : _firstTime && _password.text.length < 8
        ? 'Password minimal 8 karakter.'
        : _firstTime && _password.text != _confirm.text
        ? 'Ulangi password belum sama.'
        : null;
    if (err != null) {
      setState(() => _error = err);
      _pwShake.currentState?.shake();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = AppScope.read(context);
    try {
      if (_firstTime) {
        await state.setupAccount(_normalized!, _password.text);
      } else {
        await state.login(_normalized!, _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AreaScreen(fromLogin: true)));
    } on ApiException catch (e) {
      // Salah password: kolom bergetar, pesan merah, isian tidak dihapus.
      setState(() => _error = e.message);
      _pwShake.currentState?.shake();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// "Bukan saya?" / "Lupakan perangkat ini": hapus nomor & password tersimpan, kembali ke langkah nomor.
  Future<void> _forget() async {
    await AppScope.read(context).forgetDevice();
    if (!mounted) return;
    setState(() {
      _phone.clear();
      _password.clear();
      _confirm.clear();
      _autofilled = false;
      _error = null;
      _step = 0;
    });
    showToast(context, 'Nomor & password dihapus dari perangkat ini');
  }

  void _back() => setState(() {
    _step = 0;
    _error = null;
  });

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final top = MediaQuery.of(context).padding.top;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: context.surface,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(
          builder: (context, cs) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: cs.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: reduce ? Duration.zero : PK.step,
                      curve: Curves.easeInOut,
                      height: (_step == 0 ? 270 : 230) + top,
                      child: RedWaveHeader(
                        height: (_step == 0 ? 270 : 230) + top,
                        child: Padding(
                          padding: EdgeInsets.only(top: top + (_step == 0 ? 72 : 40)),
                          child: const Align(alignment: Alignment.topCenter, child: BrandMark(logoSize: 60)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                      child: AnimatedSwitcher(
                        duration: reduce ? const Duration(milliseconds: 150) : PK.step,
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        transitionBuilder: (child, a) {
                          if (reduce) return FadeTransition(opacity: a, child: child);
                          final incoming = (child.key as ValueKey<int>).value == _step;
                          final dx = incoming ? (_step == 1 ? 1.0 : -1.0) : (_step == 1 ? -1.0 : 1.0);
                          return FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(begin: Offset(dx * 0.35, 0), end: Offset.zero).animate(a),
                              child: child,
                            ),
                          );
                        },
                        child: _step == 0 ? _phoneStep() : _passwordStep(),
                      ),
                    ),
                    const Spacer(),
                    const SkylineIllustration(height: 140),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _title => Theme.of(context).textTheme.headlineSmall!.copyWith(fontSize: 34, height: 1.15, fontWeight: FontWeight.w800);

  Widget _phoneStep() {
    final t = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Masuk', style: _title),
        const SizedBox(height: 6),
        Text('Gunakan nomor telepon yang terdaftar.', style: t.bodyLarge?.copyWith(fontSize: 17, color: context.ink2)),
        const SizedBox(height: 22),
        Shake(
          key: _phoneShake,
          child: _InputBox(
            error: _error != null,
            child: Row(
              children: [
                Icon(Icons.phone_rounded, color: context.ink2),
                const SizedBox(width: 12),
                Text('+62', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumberNational],
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _next(),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13), _DashFormatter()],
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.5),
                    decoration: const InputDecoration(
                      hintText: '812-3456-7890',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                AnimatedScale(
                  scale: _phoneValid ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Semantics(
                    label: 'Nomor valid',
                    child: const CircleAvatar(
                      radius: 13,
                      backgroundColor: PK.green,
                      child: Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ErrorText(_error),
        if (state.savedPhone != null)
          Center(
            child: TextButton(
              onPressed: _forget,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: context.dangerText),
              child: const Text(
                'Bukan saya?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
              ),
            ),
          )
        else
          const SizedBox(height: 16),
        const SizedBox(height: 8),
        PrimaryButton(label: 'Lanjut', trailingIcon: Icons.arrow_forward_rounded, color: PK.red, onPressed: _next, loading: _loading),
        const SizedBox(height: 16),
        Text(
          'Nomor terdaftar = nomor yang dimasukkan di menu Nomor Darurat aplikasi toko, kantor, sekolah, atau warga.',
          textAlign: TextAlign.center,
          style: t.bodySmall,
        ),
      ],
    );
  }

  Widget _passwordStep() {
    final t = Theme.of(context).textTheme;
    final lines = _check?.contactLines ?? const <String>[];
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_firstTime ? 'Buat password' : 'Masuk', style: _title),
        if (_firstTime) ...[
          const SizedBox(height: 6),
          Text('Halo${_check!.name.isEmpty ? '' : ', ${_check!.name}'}. Ini login pertama Anda.', style: t.bodyLarge?.copyWith(color: context.ink2)),
        ],
        const SizedBox(height: 18),
        _InputBox(
          muted: true,
          child: Row(
            children: [
              Icon(Icons.phone_rounded, color: context.ink2),
              const SizedBox(width: 12),
              Text('+62', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(dashLocal(_digits), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                ),
              ),
              TextButton(
                onPressed: _back,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: context.dangerText),
                child: const Text(
                  'Ubah',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
        if (lines.isNotEmpty && _firstTime) ...[
          const SizedBox(height: 12),
          _InfoBox(icon: Icons.verified_user_rounded, color: PK.green, text: 'Terdaftar sebagai Nomor Darurat: ${lines.join('; ')}'),
        ],
        const SizedBox(height: 14),
        Shake(
          key: _pwShake,
          child: Column(
            children: [
              _PasswordBox(
                controller: _password,
                obscure: _obscure,
                error: _error != null,
                hint: _firstTime ? 'Password baru (min. 8 karakter)' : 'Password',
                autofocus: _password.text.isEmpty,
                onToggle: () => setState(() => _obscure = !_obscure),
                onSubmitted: _firstTime ? null : (_) => _login(),
              ),
              if (_firstTime) ...[
                const SizedBox(height: 12),
                _PasswordBox(
                  controller: _confirm,
                  obscure: _obscure,
                  error: _error != null,
                  hint: 'Ulangi password',
                  onToggle: () => setState(() => _obscure = !_obscure),
                  onSubmitted: (_) => _login(),
                ),
              ],
            ],
          ),
        ),
        _ErrorText(_error),
        const SizedBox(height: 16),
        PrimaryButton(label: _firstTime ? 'Buat password & masuk' : 'Masuk', onPressed: _login, loading: _loading),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _forget,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: context.ink2),
            child: const Text(
              'Lupakan perangkat ini',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _autofilled && !_firstTime
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: _InfoBox(icon: Icons.info_outline_rounded, color: Color(0xFF2A78D6), text: 'Terisi otomatis dari perangkat ini', center: true),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Kotak isian putih membulat dengan bingkai abu tipis dan bayangan lembut (gaya mockup).
class _InputBox extends StatelessWidget {
  const _InputBox({required this.child, this.error = false, this.muted = false});
  final Widget child;
  final bool error, muted;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: muted ? (context.isDark ? PK.darkSurface : const Color(0xFFF7F8FA)) : context.surface,
      borderRadius: BorderRadius.circular(PK.rButton),
      border: Border.all(color: error ? context.danger : context.hairline, width: error ? 1.5 : 1),
      boxShadow: muted || context.isDark ? null : const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))],
    ),
    child: child,
  );
}

class _PasswordBox extends StatelessWidget {
  const _PasswordBox({
    required this.controller,
    required this.obscure,
    required this.error,
    required this.hint,
    required this.onToggle,
    this.onSubmitted,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final bool obscure, error, autofocus;
  final String hint;
  final VoidCallback onToggle;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => _InputBox(
    error: error,
    child: Row(
      children: [
        Icon(Icons.lock_outline_rounded, color: context.ink2),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscure,
            obscuringCharacter: '●',
            autofocus: autofocus,
            autofillHints: const [AutofillHints.password],
            textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.done,
            onSubmitted: onSubmitted,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: obscure ? 3 : 0.5),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.ink2, letterSpacing: 0),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        IconButton(
          tooltip: obscure ? 'Tampilkan password' : 'Sembunyikan password',
          onPressed: onToggle,
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: context.ink2),
        ),
      ],
    ),
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.color, required this.text, this.center = false});
  final IconData icon;
  final Color color;
  final String text;
  final bool center;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: context.isDark ? 0.18 : 0.08),
      borderRadius: BorderRadius.circular(PK.rField),
    ),
    child: Row(
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Flexible(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.ink)),
        ),
      ],
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String? text;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 150),
    child: text == null
        ? const SizedBox(width: double.infinity)
        : Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: context.dangerText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text!,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.dangerText),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

/// Ketik "81234567890" → tampil "812-3456-7890".
class _DashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = dashLocal(newValue.text.replaceFirst(RegExp(r'^(62|0)'), ''));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
