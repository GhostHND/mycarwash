import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

typedef DashboardCallback = Future<void> Function(BuildContext context);

class MyCarWashLoginScreen extends StatefulWidget {
  const MyCarWashLoginScreen({super.key, required this.onEnterDashboard});

  final DashboardCallback onEnterDashboard;

  @override
  State<MyCarWashLoginScreen> createState() => _MyCarWashLoginScreenState();
}

class _MyCarWashLoginScreenState extends State<MyCarWashLoginScreen> {
  static const _api = 'http://127.0.0.1:8000/api/v1';

  static const _turquoise = Color(0xFF0FA7B4);
  static const _coral = Color(0xFFE84657);
  static const _background = Color(0xFF03090B);
  static const _muted = Color(0xFF84939B);
  static const _field = Color(0xFF202D3F);

  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  bool get _canSubmit =>
      !_loading && _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _email.addListener(_refresh);
    _password.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_canSubmit) return;

    final email = _email.text.trim().toLowerCase();

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Introduce un correo electrónico válido.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    String? token;

    try {
      final response = await http
          .post(
            Uri.parse('$_api/auth/token'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'email': email,
              'password': _password.text,
              'device_name': 'adn-mycarwash-web-local',
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 422 || response.statusCode == 401) {
        throw const _LoginError('Correo o contraseña incorrectos.');
      }

      if (response.statusCode == 403) {
        throw const _LoginError(
          'Tu cuenta no tiene acceso a una empresa activa.',
        );
      }

      if (response.statusCode != 200) {
        throw _LoginError(
          'No se pudo iniciar sesión. Código ${response.statusCode}.',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      token = json['access_token'] as String?;

      if (token == null || token.isEmpty) {
        throw const _LoginError('El servidor no devolvió una sesión válida.');
      }

      final profile = await http
          .get(
            Uri.parse('$_api/me'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (profile.statusCode != 200) {
        throw const _LoginError('No se pudo validar el acceso a la empresa.');
      }

      final profileData = jsonDecode(profile.body) as Map<String, dynamic>;

      final companies = profileData['companies'];

      if (companies is! List || companies.isEmpty) {
        throw const _LoginError('No tienes ninguna empresa autorizada.');
      }

      if (!mounted) return;

      _password.clear();

      // El dashboard existente se conserva.
      // El acceso se produce solo despues del login real.
      await widget.onEnterDashboard(context);
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'La conexión tardó demasiado. Intenta de nuevo.',
        );
      }
    } on _LoginError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo conectar con Laravel. '
              'Comprueba que el servidor local esté iniciado.';
        });
      }
    } finally {
      // No guardar tokens permanentes en el navegador.
      if (token != null) {
        try {
          await http
              .post(
                Uri.parse('$_api/auth/logout'),
                headers: {
                  'Accept': 'application/json',
                  'Authorization': 'Bearer $token',
                },
              )
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // El token tambien tiene vencimiento en el servidor.
        }
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 900;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 44 > 0
                            ? constraints.maxHeight - 44
                            : 0,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xFF071013),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: const Color(0xFF203039),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 55,
                                  offset: const Offset(0, 24),
                                ),
                              ],
                            ),
                            child: desktop
                                ? SizedBox(
                                    height: 592,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 54,
                                          child: _brandSection(),
                                        ),
                                        Container(
                                          width: 1,
                                          color: const Color(0xFF203039),
                                        ),
                                        Expanded(
                                          flex: 46,
                                          child: _formSection(),
                                        ),
                                      ],
                                    ),
                                  )
                                : _formSection(mobile: true),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandSection() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF07272C),
                  Color(0xFF061619),
                  Color(0xFF171018),
                ],
              ),
            ),
          ),
        ),
        const Positioned(bottom: -170, left: -135, child: _WashRings()),
        Padding(
          padding: const EdgeInsets.fromLTRB(42, 40, 35, 39),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrowPill(),
              const SizedBox(height: 35),
              const Text(
                'Tu CarWash.',
                style: TextStyle(
                  fontSize: 47,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.9,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [_turquoise, Color(0xFF28C5CB), _coral],
                ).createShader(bounds),
                blendMode: BlendMode.srcIn,
                child: const Text(
                  'Todo bajo control.',
                  style: TextStyle(
                    fontSize: 43,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.7,
                    color: Colors.white,
                    height: 1.18,
                  ),
                ),
              ),
              const SizedBox(height: 25),
              const Text(
                'Lavados, reservas, clientes, personal, '
                'inventario y ventas conectados en un solo lugar.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFFA4B5BD),
                  height: 1.8,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  _brandLogo(78),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'ADN ',
                                style: TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: 'MyCarWash',
                                style: TextStyle(color: _turquoise),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'UN PRODUCTO DE ADN PUBLICIDAD',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.0,
                            color: Color(0xFF9BAEB6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formSection({bool mobile = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? 25 : 46,
        mobile ? 33 : 56,
        mobile ? 25 : 46,
        mobile ? 34 : 44,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mobile) ...[
            Row(
              children: [
                _brandLogo(58),
                const SizedBox(width: 12),
                const Text(
                  'ADN MyCarWash',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 34),
          ],
          const Text(
            'ACCESO PRIVADO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: _turquoise,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Bienvenido de nuevo',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Ingresa tus credenciales para continuar '
            'al centro de operaciones.',
            style: TextStyle(fontSize: 12, height: 1.6, color: _muted),
          ),
          const SizedBox(height: 32),
          _label('CORREO ELECTRÓNICO'),
          const SizedBox(height: 8),
          _input(
            controller: _email,
            hint: 'correo@empresa.com',
            icon: Icons.mail_outline_rounded,
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
          ),
          const SizedBox(height: 19),
          _label('CONTRASEÑA'),
          const SizedBox(height: 8),
          _input(
            controller: _password,
            hint: 'Ingresa tu contraseña',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            autofill: const [AutofillHints.password],
            suffix: IconButton(
              tooltip: _obscurePassword
                  ? 'Mostrar contraseña'
                  : 'Ocultar contraseña',
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: _muted,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF8995), fontSize: 12),
            ),
          ],
          const SizedBox(height: 25),
          Container(
            width: double.infinity,
            height: 51,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0FA7B4),
                  Color(0xFF20BAC6),
                  Color(0xFFE84657),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _turquoise.withValues(alpha: 0.15),
                  blurRadius: 25,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _canSubmit ? _login : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 21,
                      width: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Iniciar sesión',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 30),
          const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined, size: 15, color: _turquoise),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Acceso protegido · ADN MyCarWash',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
              ],
            ),
          ),
          if (mobile) ...[
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Powered by ADN Publicidad',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eyebrowPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: _turquoise.withValues(alpha: 0.09),
        border: Border.all(color: _turquoise.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_car_wash_outlined, size: 17, color: _turquoise),
          SizedBox(width: 8),
          Text(
            'Centro de operaciones',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2BC8D1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandLogo(double size) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.09),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Image.asset(
        'assets/branding/logo_adn.png',
        fit: BoxFit.contain,
        semanticLabel: 'Logotipo oficial de ADN Publicidad',
      ),
    );
  }

  Widget _label(String value) {
    return Text(
      value,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: Color(0xFF98A8B0),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    bool obscure = false,
    List<String>? autofill,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      autofillHints: autofill,
      obscureText: obscure,
      enabled: !_loading,
      onSubmitted: (_) => _login(),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8797A4), fontSize: 12),
        filled: true,
        fillColor: _field,
        prefixIcon: Icon(icon, size: 19, color: _muted),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF344356)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF344356)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _turquoise, width: 1.5),
        ),
      ),
    );
  }
}

class _LoginError implements Exception {
  const _LoginError(this.message);
  final String message;
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.9, -0.7),
                radius: 1.65,
                colors: [
                  Color(0xFF073036),
                  Color(0xFF040C0E),
                  Color(0xFF03090B),
                ],
                stops: [0, 0.58, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        Positioned(
          right: -180,
          bottom: -260,
          child: Container(
            width: 650,
            height: 650,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFE84657).withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF426168).withValues(alpha: 0.095)
      ..strokeWidth = 0.7;

    for (double x = 0; x < size.width; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += 52) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WashRings extends StatelessWidget {
  const _WashRings();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      width: 420,
      child: CustomPaint(painter: _WashRingPainter()),
    );
  }
}

class _WashRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .50, size.height * .5);

    for (final radius in [100.0, 148.0, 197.0]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 25
          ..color = const Color(0xFF0FA7B4).withValues(alpha: 0.11),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
