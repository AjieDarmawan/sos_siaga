import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'splash_screen.dart' show MerahPutih;

/// Login (mockup A2): header navy + lambang + "Akses khusus petugas", kartu "Masuk Petugas" berisi Nomor HP dan
/// Kata sandi. Nomor dicek dulu (Nomor Darurat); bila belum punya kata sandi, kartu berubah menjadi "Buat kata sandi"
/// (login pertama, tanpa OTP). Nomor & sandi bisa disimpan di perangkat untuk login cepat.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.justLoggedOut = false});
  final bool justLoggedOut;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _shake = GlobalKey<ShakeState>();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;
  bool _prefilled = false;
  String? _error;
  PhoneCheck? _check;
  String? _checkedDigits;

  bool get _firstTime => _check != null && !_check!.hasPassword && _checkedDigits == _digits;
  String get _digits => _phone.text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^(62|0)'), '');
  bool get _phoneValid => _digits.length >= 9 && _digits.startsWith('8');

  @override
  void initState() {
    super.initState();
    _phone.addListener(() {
      // Nomor diganti setelah dicek → kembali ke mode masuk biasa.
      if (_check != null && _checkedDigits != _digits) setState(() => _check = null);
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
      if (s.hasSavedPassword) s.savedPassword().then((p) => mounted && p != null ? _password.text = p : null);
    }
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    _shake.currentState?.shake();
  }

  Future<void> _submit() async {
    if (!_phoneValid) return _fail('Masukkan nomor HP yang benar, mis. 812-3456-7890.');
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = AppScope.read(context);
    try {
      if (_check == null || _checkedDigits != _digits) {
        _check = await state.checkPhone('62$_digits');
        _checkedDigits = _digits;
        if (_firstTime) {
          // Login pertama: minta buat kata sandi dulu.
          setState(() {
            _password.clear();
            _confirm.clear();
          });
          return;
        }
      }
      if (_password.text.isEmpty) return _fail(_firstTime ? 'Buat kata sandi minimal 8 karakter.' : 'Masukkan kata sandi.');
      if (_firstTime) {
        if (_password.text.length < 8) return _fail('Kata sandi minimal 8 karakter.');
        if (_password.text != _confirm.text) return _fail('Ulangi kata sandi belum sama.');
        await state.setupAccount(_check!.phone, _password.text, remember: _remember);
      } else {
        await state.login(_check!.phone, _password.text, remember: _remember);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } on ApiException catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forget() async {
    await AppScope.read(context).forgetDevice();
    if (!mounted) return;
    setState(() {
      _phone.clear();
      _password.clear();
      _confirm.clear();
      _check = null;
      _error = null;
    });
    showToast(context, 'Nomor & kata sandi dihapus dari perangkat ini');
  }

  void _help({bool reset = false}) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(reset ? 'Lupa kata sandi' : 'Bantuan masuk'),
      content: Text(
        reset
            ? 'Kata sandi tidak bisa diatur ulang dari aplikasi. Minta admin Polsek atau pengelola aplikasi yang mendaftarkan nomor Anda untuk mengatur ulang akun.'
            : 'Nomor Anda harus didaftarkan lebih dulu di menu Nomor Darurat aplikasi mitra (toko, kantor, sekolah, atau warga). '
                  'Bila sudah terdaftar tapi tetap tidak bisa masuk, hubungi admin Polsek.',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mengerti'))],
    ),
  );

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: context.pageBg,
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).padding.bottom),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const NavyHeader(
                        radius: 38,
                        padding: EdgeInsets.fromLTRB(24, 18, 24, 86),
                        child: Center(
                          child: Column(
                            children: [
                              PolmasEmblem(size: 58),
                              SizedBox(height: 10),
                              Text('Polmas Digital', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                              SizedBox(height: 4),
                              Text('Aplikasi Petugas Polisi Masyarakat', style: TextStyle(fontSize: 13, color: PK.headerMute)),
                              SizedBox(height: 12),
                              _GoldChip('AKSES KHUSUS PETUGAS'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Transform.translate(offset: const Offset(0, -50), child: _card(state)),
                  Transform.translate(
                    offset: const Offset(0, -34),
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.isDark ? const Color(0x22D4A82A) : const Color(0xFFFFF8E6),
                            border: Border.all(color: context.isDark ? const Color(0x55D4A82A) : const Color(0xFFF4E2A8)),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFFB98A0E)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Login pertama? Anda akan diminta membuat kata sandi. Nomor didaftarkan admin di daftar Nomor Darurat.',
                                  style: TextStyle(fontSize: 12, height: 1.45, color: context.isDark ? const Color(0xFFF5E3B0) : const Color(0xFF6B5310)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (state.savedPhone != null)
                          TextButton(
                            onPressed: _forget,
                            child: Text('Bukan nomor Anda? Lupakan perangkat ini', style: TextStyle(color: context.ink2, decoration: TextDecoration.underline)),
                          ),
                        TextButton(
                          onPressed: _help,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Butuh bantuan? '),
                                TextSpan(text: 'Hubungi Admin Polsek', style: TextStyle(fontWeight: FontWeight.w700, color: context.brand)),
                              ],
                            ),
                            style: TextStyle(fontSize: 12.5, color: context.ink2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: MerahPutih(height: 4)),
          ],
        ),
      ),
    );
  }

  Widget _card(AppState state) {
    final lines = _check?.contactLines ?? const <String>[];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x4D0B2A6F), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -14)],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_firstTime ? 'Buat Kata Sandi' : 'Masuk Petugas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
            const SizedBox(height: 4),
            Text(
              _firstTime
                  ? 'Halo${_check!.name.isEmpty ? '' : ', ${_check!.name}'}. Ini login pertama Anda, buat kata sandi minimal 8 karakter.'
                  : 'Gunakan nomor HP yang terdaftar sebagai Nomor Darurat.',
              style: TextStyle(fontSize: 13, height: 1.45, color: context.ink2),
            ),
            if (_firstTime && lines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Terdaftar sebagai: ${lines.join('; ')}', style: const TextStyle(fontSize: 12, color: PK.greenDark, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 18),
            Shake(
              key: _shake,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Nomor HP'),
                  _Field(
                    focusedLook: true,
                    error: _error != null && !_phoneValid,
                    child: Row(
                      children: [
                        Text('+62', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.brand)),
                        Container(width: 1.5, height: 22, margin: const EdgeInsets.symmetric(horizontal: 10), color: context.hairline),
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [AutofillHints.telephoneNumberNational],
                            textInputAction: TextInputAction.next,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13), _DashFormatter()],
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.ink),
                            decoration: _bare('812 3456 7890'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label(_firstTime ? 'Kata sandi baru' : 'Kata sandi'),
                  _passwordField(_password, _firstTime ? 'Minimal 8 karakter' : 'Kata sandi', done: !_firstTime),
                  if (_firstTime) ...[
                    const SizedBox(height: 12),
                    _label('Ulangi kata sandi'),
                    _passwordField(_confirm, 'Ulangi kata sandi', done: true),
                  ],
                ],
              ),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.dangerText)),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _remember = !_remember),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _remember ? PK.navy : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: _remember ? PK.navy : context.hairline, width: 1.5),
                          ),
                          child: _remember ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 8),
                        Text('Ingat di perangkat ini', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.ink)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (!_firstTime)
                  InkWell(
                    onTap: () => _help(reset: true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('Lupa sandi?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.brand)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _NavyButton(label: _firstTime ? 'Buat kata sandi & masuk' : 'Masuk', loading: _loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.ink2)),
  );

  InputDecoration _bare(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.ink2.withValues(alpha: 0.6), fontWeight: FontWeight.w500, letterSpacing: 0),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    filled: false,
    isCollapsed: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 15),
  );

  Widget _passwordField(TextEditingController c, String hint, {required bool done}) => _Field(
    error: _error != null && _phoneValid,
    child: Row(
      children: [
        const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: c,
            obscureText: _obscure,
            obscuringCharacter: '•',
            autofillHints: [_firstTime ? AutofillHints.newPassword : AutofillHints.password],
            textInputAction: done ? TextInputAction.done : TextInputAction.next,
            onSubmitted: done ? (_) => _submit() : null,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: _obscure ? 3 : 0.4, color: context.ink),
            decoration: _bare(hint),
          ),
        ),
        IconButton(
          tooltip: _obscure ? 'Tampilkan kata sandi' : 'Sembunyikan kata sandi',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: const Color(0xFF94A3B8)),
        ),
      ],
    ),
  );
}

class _GoldChip extends StatelessWidget {
  const _GoldChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: PK.gold2.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: PK.gold2)),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.child, this.focusedLook = false, this.error = false});
  final Widget child;
  final bool focusedLook, error;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.only(left: 14, right: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: error
            ? context.danger
            : focusedLook
            ? context.brand
            : (context.isDark ? context.hairline : const Color(0xFFD5DCE8)),
        width: 1.5,
      ),
      boxShadow: focusedLook && !error ? const [BoxShadow(color: Color(0x140B2A6F), spreadRadius: 4)] : null,
    ),
    child: child,
  );
}

class _NavyButton extends StatelessWidget {
  const _NavyButton({required this.label, required this.onPressed, this.loading = false});
  final String label;
  final VoidCallback onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF123A94), PK.navy]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0xCC0B2A6F), blurRadius: 22, offset: Offset(0, 12), spreadRadius: -12)],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onPressed,
          child: SizedBox(
            height: 52,
            child: Center(
              child: loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 19, color: PK.gold2),
                        const SizedBox(width: 8),
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Format nomor saat diketik: 812-3456-7890.
class _DashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = dashLocal(newValue.text);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
