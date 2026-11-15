import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyCarWashApp());
}

class AdnColors {
  static const night = Color(0xFF05090B);
  static const sidebar = Color(0xFF061115);
  static const panel = Color(0xFF0A1317);
  static const panelLight = Color(0xFF102027);
  static const border = Color(0xFF21333B);
  static const turquoise = Color(0xFF0FA7B4);
  static const turquoiseLight = Color(0xFF22C6D2);
  static const coral = Color(0xFFE84657);
  static const orange = Color(0xFFED7E24);
  static const yellow = Color(0xFFF5C000);
  static const white = Color(0xFFF5FAFC);
  static const muted = Color(0xFF9AAFB7);
}

class MyCarWashApp extends StatelessWidget {
  const MyCarWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ADN MyCarWash',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AdnColors.night,
        colorScheme: const ColorScheme.dark(
          primary: AdnColors.turquoise,
          secondary: AdnColors.coral,
          surface: AdnColors.panel,
          onSurface: AdnColors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AdnColors.panelLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdnColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdnColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AdnColors.turquoise,
              width: 1.5,
            ),
          ),
          labelStyle: const TextStyle(color: AdnColors.muted),
        ),
      ),
      home: const LoginPreview(),
    );
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 76});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.09),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        boxShadow: [
          BoxShadow(
            color: AdnColors.turquoise.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Image.asset(
        'assets/branding/logo_adn.png',
        fit: BoxFit.contain,
        semanticLabel: 'Logotipo original de ADN Publicidad',
      ),
    );
  }
}

class LoginPreview extends StatefulWidget {
  const LoginPreview({super.key});

  @override
  State<LoginPreview> createState() => _LoginPreviewState();
}

class _LoginPreviewState extends State<LoginPreview> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool hidePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 950;
          return Stack(
            children: [
              const Positioned.fill(child: _BackgroundGlow()),
              Row(
                children: [
                  if (desktop)
                    const Expanded(flex: 5, child: _BrandPresentation()),
                  Expanded(
                    flex: desktop ? 5 : 1,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: _buildLoginPanel(desktop),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginPanel(bool desktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!desktop) ...[
          const BrandLogo(size: 72),
          const SizedBox(height: 22),
        ],
        const _Eyebrow(text: 'PLATAFORMA DE GESTIÓN'),
        const SizedBox(height: 14),
        const Text(
          'Bienvenido a\nMyCarWash',
          style: TextStyle(
            color: AdnColors.white,
            fontSize: 37,
            height: 1.14,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Toda la operación de tu autolavado, en un solo lugar.',
          style: TextStyle(fontSize: 15, color: AdnColors.muted, height: 1.5),
        ),
        const SizedBox(height: 30),
        _Panel(
          child: Padding(
            padding: const EdgeInsets.all(23),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Iniciar sesión',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AdnColors.white,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Acceso para administradores y personal autorizado.',
                  style: TextStyle(color: AdnColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 25),
                const _FieldLabel('Correo electrónico'),
                const SizedBox(height: 8),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'correo@empresa.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 20),
                const _FieldLabel('Contraseña'),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: hidePassword,
                  decoration: InputDecoration(
                    hintText: 'Ingresa tu contraseña',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      tooltip: hidePassword
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () =>
                          setState(() => hidePassword = !hidePassword),
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 51,
                  child: FilledButton.icon(
                    onPressed:
                        null, // Se activará al implementar autenticación real.
                    icon: const Icon(Icons.login_rounded, size: 19),
                    label: const Text('Ingresar'),
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: AdnColors.turquoise.withValues(
                        alpha: 0.23,
                      ),
                      disabledForegroundColor: AdnColors.white.withValues(
                        alpha: 0.60,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Inicio de sesión deshabilitado: API y MySQL aún no conectados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AdnColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AdnColors.turquoiseLight,
              side: const BorderSide(color: AdnColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DashboardPreview()),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 19),
            label: const Text('Ver vista previa del dashboard'),
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'PROTOTIPO VISUAL · SIN ACCESO A DATOS REALES',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: AdnColors.muted),
          ),
        ),
      ],
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.9, -0.8),
          radius: 1.6,
          colors: [Color(0xFF0D313A), AdnColors.night, AdnColors.night],
          stops: [0, 0.52, 1],
        ),
      ),
    );
  }
}

class _BrandPresentation extends StatelessWidget {
  const _BrandPresentation();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(65),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AdnColors.border)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(size: 90),
          const SizedBox(height: 34),
          const _Eyebrow(text: 'UN PRODUCTO DE ADN PUBLICIDAD'),
          const SizedBox(height: 17),
          const Text(
            'Administración\nque se mueve\ncontigo.',
            style: TextStyle(
              fontSize: 49,
              height: 1.13,
              color: AdnColors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 380),
            child: Text(
              'Gestiona servicios, clientes, equipo, agenda y sucursales desde una sola plataforma.',
              style: TextStyle(
                fontSize: 16,
                height: 1.55,
                color: AdnColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeatureChip(icon: Icons.car_repair_rounded, label: 'Lavados'),
              _FeatureChip(
                icon: Icons.calendar_month_rounded,
                label: 'Reservas',
              ),
              _FeatureChip(icon: Icons.groups_rounded, label: 'Personal'),
              _FeatureChip(icon: Icons.analytics_outlined, label: 'Reportes'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
    decoration: BoxDecoration(
      color: AdnColors.panelLight,
      border: Border.all(color: AdnColors.border),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AdnColors.turquoiseLight),
        const SizedBox(width: 9),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.9,
      color: AdnColors.turquoiseLight,
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: AdnColors.white, fontWeight: FontWeight.w600),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdnColors.panel,
      border: Border.all(color: AdnColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );
}

class _NavItem {
  const _NavItem(this.title, this.icon);
  final String title;
  final IconData icon;
}

const _menu = [
  _NavItem('Resumen', Icons.dashboard_outlined),
  _NavItem('Lavados', Icons.local_car_wash_outlined),
  _NavItem('Reservas', Icons.event_available_outlined),
  _NavItem('Clientes', Icons.people_outline_rounded),
  _NavItem('Vehículos', Icons.directions_car_outlined),
  _NavItem('Empleados', Icons.badge_outlined),
  _NavItem('Inventario', Icons.inventory_2_outlined),
  _NavItem('Caja y ventas', Icons.point_of_sale_outlined),
  _NavItem('Sitio web', Icons.language_outlined),
  _NavItem('Configuración', Icons.settings_outlined),
];

class DashboardPreview extends StatefulWidget {
  const DashboardPreview({super.key});

  @override
  State<DashboardPreview> createState() => _DashboardPreviewState();
}

class _DashboardPreviewState extends State<DashboardPreview> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MediaQuery.sizeOf(context).width < 900
          ? AppBar(
              backgroundColor: AdnColors.sidebar,
              title: Text(_menu[selected].title),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(
                    Icons.circle,
                    color: AdnColors.turquoise,
                    size: 12,
                  ),
                ),
              ],
            )
          : null,
      drawer: MediaQuery.sizeOf(context).width < 900
          ? Drawer(
              backgroundColor: AdnColors.sidebar,
              child: SafeArea(child: _sidebar()),
            )
          : null,
      body: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 900)
            SizedBox(width: 260, child: _sidebar()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: _mainContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    return Container(
      color: AdnColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
            child: Row(
              children: [
                const BrandLogo(size: 52),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADN MyCarWash',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'PANEL ADMINISTRATIVO',
                        style: TextStyle(fontSize: 9, color: AdnColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AdnColors.border, height: 1),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _menu.length,
              itemBuilder: (context, index) {
                final item = _menu[index];
                final active = selected == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    selected: active,
                    selectedTileColor: AdnColors.turquoise.withValues(
                      alpha: 0.16,
                    ),
                    leading: Icon(
                      item.icon,
                      color: active
                          ? AdnColors.turquoiseLight
                          : AdnColors.muted,
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        color: active ? AdnColors.white : AdnColors.muted,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      setState(() => selected = index);
                      if (MediaQuery.sizeOf(context).width < 900) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                );
              },
            ),
          ),
          const Divider(color: AdnColors.border, height: 1),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Volver al inicio'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(15, 0, 15, 16),
            child: Text(
              'VISTA PREVIA · SIN DATOS',
              style: TextStyle(fontSize: 10, color: AdnColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainContent() {
    final isHome = selected == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _Eyebrow(text: 'ADN PUBLICIDAD · SOFTWARE')),
            const Icon(Icons.shield_outlined, color: AdnColors.turquoise),
            const SizedBox(width: 8),
            const Text(
              'Vista previa',
              style: TextStyle(fontSize: 12, color: AdnColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          isHome ? 'Resumen general' : _menu[selected].title,
          style: const TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w800,
            color: AdnColors.white,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Interfaz en construcción. La conexión real a MySQL se realizará después.',
          style: TextStyle(color: AdnColors.muted),
        ),
        const SizedBox(height: 24),
        if (isHome) ...[
          LayoutBuilder(
            builder: (context, size) {
              final cellWidth = size.maxWidth >= 900
                  ? (size.maxWidth - 42) / 4
                  : size.maxWidth >= 540
                  ? (size.maxWidth - 14) / 2
                  : size.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _StatCard(
                    'Lavados activos',
                    Icons.local_car_wash_outlined,
                    cellWidth,
                    AdnColors.turquoise,
                  ),
                  _StatCard(
                    'En espera',
                    Icons.hourglass_empty_rounded,
                    cellWidth,
                    AdnColors.orange,
                  ),
                  _StatCard(
                    'Reservas de hoy',
                    Icons.calendar_month_outlined,
                    cellWidth,
                    AdnColors.yellow,
                  ),
                  _StatCard(
                    'Ventas de hoy',
                    Icons.payments_outlined,
                    cellWidth,
                    AdnColors.coral,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 23),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Actividad de lavados',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 35),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.car_crash_outlined,
                          size: 53,
                          color: AdnColors.muted.withValues(alpha: .6),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Aún no hay operaciones para mostrar',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Conectaremos estos datos al crear la API y MySQL.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AdnColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),
                ],
              ),
            ),
          ),
        ] else
          _Panel(
            child: const Padding(
              padding: EdgeInsets.all(30),
              child: Row(
                children: [
                  Icon(
                    Icons.construction_outlined,
                    color: AdnColors.turquoiseLight,
                    size: 28,
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      'Sección visual reservada. Implementaremos este módulo '
                      'con su código y datos reales en los próximos pasos.',
                      style: TextStyle(color: AdnColors.muted, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.icon, this.width, this.accent);
  final String label;
  final IconData icon;
  final double width;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _Panel(
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 25),
            const SizedBox(height: 19),
            const Text(
              '—',
              style: TextStyle(fontSize: 31, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AdnColors.muted)),
          ],
        ),
      ),
    ),
  );
}
