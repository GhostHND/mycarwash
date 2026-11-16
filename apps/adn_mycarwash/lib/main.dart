import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

import 'core/business_identity.dart';
import 'ui/mycarwash_login.dart';
import 'ui/company_settings_page.dart';
import 'ui/company_operations_page.dart';
import 'ui/company_wash_workflow_page.dart';
import 'ui/company_booking_page.dart';
import 'ui/company_inventory_page.dart';
import 'ui/company_cash_page.dart';

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
      builder: (context, child) {
        final currentTheme = Theme.of(context);

        return Theme(
          data: currentTheme.copyWith(
            textTheme: GoogleFonts.interTextTheme(currentTheme.textTheme),
            primaryTextTheme: GoogleFonts.interTextTheme(
              currentTheme.primaryTextTheme,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MyCarWashLoginScreen(
        onEnterDashboard: (context) async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const DashboardPreview()),
          );
        },
      ),
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
  _NavItem('Servicios', Icons.design_services_outlined),
  _NavItem('Puestos de lavado', Icons.grid_view_outlined),
  _NavItem('Órdenes de lavado', Icons.local_car_wash_outlined),
  _NavItem('Asignaciones', Icons.groups_outlined),
  _NavItem('Cola de lavado', Icons.view_list_outlined),
  _NavItem('Turnos de trabajo', Icons.work_history_outlined),
  _NavItem('Asignaciones de turnos', Icons.assignment_ind_outlined),
  _NavItem('Bloqueos de agenda', Icons.event_busy_outlined),
  _NavItem('Inventario', Icons.inventory_2_outlined),
  _NavItem('Categorías de inventario', Icons.category_outlined),
  _NavItem('Proveedores', Icons.local_shipping_outlined),
  _NavItem('Movimientos de inventario', Icons.swap_horiz_outlined),
  _NavItem('Caja y ventas', Icons.point_of_sale_outlined),
  _NavItem('Sesiones de caja', Icons.pending_actions_outlined),
  _NavItem('Categorías de egresos', Icons.category_outlined),
  _NavItem('Movimientos de caja', Icons.swap_horiz_outlined),
  _NavItem('Sitio web', Icons.language_outlined),
  _NavItem('Mi Empresa', Icons.business_outlined),
  _NavItem('Configuración', Icons.settings_outlined),
];

class DashboardPreview extends StatefulWidget {
  const DashboardPreview({super.key});

  @override
  State<DashboardPreview> createState() => _DashboardPreviewState();
}

class _DashboardPreviewState extends State<DashboardPreview> {
  @override
  void initState() {
    super.initState();
    unawaited(BusinessIdentity.refresh());
  }

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
          ValueListenableBuilder<BusinessIdentityData>(
            valueListenable: BusinessIdentity.current,
            builder: (context, identity, _) {
              final logo = identity.logoBytes;

              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 5),
                child: Row(
                  children: [
                    Container(
                      width: 43,
                      height: 43,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: logo != null
                          ? Image.memory(
                              logo,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          : const Icon(
                              Icons.business_outlined,
                              color: Color(0xFF64748B),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            identity.companyName.isEmpty
                                ? 'Mi Empresa'
                                : identity.companyName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'NEGOCIO ACTIVO',
                            style: TextStyle(
                              fontSize: 9,
                              color: AdnColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
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
            label: const Text('Cerrar sesión'),
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
    if (_menu[selected].title == 'Mi Empresa') {
      return const CompanySettingsPage();
    }
    final catalog = switch (_menu[selected].title) {
      'Clientes' => OperationsCatalog.clients,
      'Vehículos' => OperationsCatalog.vehicles,
      'Empleados' => OperationsCatalog.employees,
      'Servicios' => OperationsCatalog.services,
      _ => null,
    };
    if (catalog != null) {
      return CompanyOperationsPage(catalog: catalog);
    }
    final cashModule = switch (_menu[selected].title) {
      'Caja y ventas' => CashModule.registers,
      'Sesiones de caja' => CashModule.sessions,
      'Categorías de egresos' => CashModule.categories,
      'Movimientos de caja' => CashModule.movements,
      _ => null,
    };
    if (cashModule != null) {
      return CompanyCashPage(module: cashModule);
    }
    final inventoryModule = switch (_menu[selected].title) {
      'Inventario' => InventoryModule.items,
      'Categorías de inventario' => InventoryModule.categories,
      'Proveedores' => InventoryModule.suppliers,
      'Movimientos de inventario' => InventoryModule.movements,
      _ => null,
    };
    if (inventoryModule != null) {
      return CompanyInventoryPage(module: inventoryModule);
    }
    final bookingModule = switch (_menu[selected].title) {
      'Reservas' => BookingModule.bookings,
      'Turnos de trabajo' => BookingModule.shifts,
      'Asignaciones de turnos' => BookingModule.roster,
      'Bloqueos de agenda' => BookingModule.blocks,
      _ => null,
    };
    if (bookingModule != null) {
      return CompanyBookingPage(module: bookingModule);
    }
    final washModule = switch (_menu[selected].title) {
      'Puestos de lavado' => WashModule.bays,
      'Órdenes de lavado' => WashModule.orders,
      'Asignaciones' => WashModule.assignments,
      'Cola de lavado' => WashModule.queue,
      _ => null,
    };
    if (washModule != null) {
      return CompanyWashWorkflowPage(module: washModule);
    }
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
