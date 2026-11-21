import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:google_fonts/google_fonts.dart';

import 'core/business_identity.dart';
import 'core/company_visual_theme.dart';
import 'core/mycarwash_session.dart';
import 'ui/company_users_24n2_page.dart';
import 'ui/washer_mobile_24n4.dart';
import 'ui/company_attendance_station_24n4.dart';
import 'ui/company_attendance_reports_b25d.dart';
import 'ui/company_commission_report_b25l.dart';
import 'ui/company_roster_bulk_b25d.dart';
import 'ui/mycarwash_login.dart';
import 'ui/company_billing_alerts_24n8.dart';
import 'ui/company_settings_page.dart';
import 'ui/company_monitor_devices_rpi01g_page.dart';
import 'ui/company_operations_page.dart';
import 'ui/company_wash_workflow_page.dart';
import 'ui/company_wash_monitor_24b1.dart';
import 'ui/company_booking_page.dart';
import 'ui/company_booking_daily_24d2.dart';
import 'ui/company_inventory_page.dart';
import 'ui/company_cash_page.dart';
import 'ui/company_finance_hub_24k.dart';
import 'ui/company_smart_pos_page.dart';
import 'ui/company_pos_designer_page.dart';
import 'ui/company_pos_reports_page.dart';
import 'ui/company_unified_reports_page.dart';
import 'ui/company_dashboard_24a_page.dart';
import 'ui/company_purchasing_page.dart';
import 'ui/company_sales_page.dart';

import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyCarWashApp());
}

class AdnColors {
  static Color get night => CompanyVisualTheme.background;
  static Color get sidebar => CompanyVisualTheme.sidebar;
  static Color get panel => CompanyVisualTheme.surface;
  static Color get panelLight => CompanyVisualTheme.card;
  static Color get border => CompanyVisualTheme.border;
  static Color get turquoise => CompanyVisualTheme.primary;
  static Color get turquoiseLight => CompanyVisualTheme.icon;
  static Color get coral => CompanyVisualTheme.danger;
  static Color get orange => CompanyVisualTheme.accent;
  static Color get yellow => CompanyVisualTheme.warning;
  static Color get white => CompanyVisualTheme.text;
  static Color get muted => CompanyVisualTheme.muted;
}

class MyCarWashApp extends StatelessWidget {
  const MyCarWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CompanyPalette>(
      valueListenable: CompanyVisualTheme.current,
      builder: (context, palette, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ADN MyCarWash',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AdnColors.night,
          colorScheme: ColorScheme.dark(
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
              borderSide: BorderSide(color: AdnColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AdnColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AdnColors.turquoise, width: 1.5),
            ),
            labelStyle: TextStyle(color: AdnColors.muted),
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
        home: kIsWeb && Uri.base.queryParameters['mcw_kiosk'] == 'local'
            ? (Uri.base.host == '127.0.0.1' && Uri.base.port == 8787
                ? CompanyWashMonitor24B1(
                    kioskKey: Uri.base.queryParameters['mcw_kiosk'])
                : const Scaffold(
                    body: Center(child: Text('Dispositivo no vinculado.'))))
            : MyCarWashLoginScreen(
          onEnterDashboard: (context) async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => MyCarWashSession.isWasher
                    ? const WasherMobile24N4()
                    : const DashboardPreview(),
              ),
            );
          },
        ),
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
    style: TextStyle(
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
  _NavItem('Dashboard', Icons.dashboard_outlined),
  _NavItem('Lavados', Icons.local_car_wash_outlined),
  _NavItem('Reservas', Icons.event_available_outlined),
  _NavItem('Clientes', Icons.people_outline_rounded),
  _NavItem('Vehículos', Icons.directions_car_outlined),
  _NavItem('Empleados', Icons.badge_outlined),
  _NavItem('Punto de asistencia QR', Icons.qr_code_2_outlined),
  _NavItem('Historial de asistencia', Icons.fact_check_outlined),
  _NavItem('Servicios', Icons.design_services_outlined),
  _NavItem('Puestos de lavado', Icons.grid_view_outlined),
  _NavItem('Órdenes de lavado', Icons.local_car_wash_outlined),
  _NavItem('Asignaciones', Icons.groups_outlined),
  _NavItem('Cola de lavado', Icons.view_list_outlined),
  _NavItem('Turnos de trabajo', Icons.work_history_outlined),
  _NavItem('Asignaciones de turnos', Icons.assignment_ind_outlined),
  _NavItem('Reporte mensual de asistencia', Icons.calendar_month_outlined),
  _NavItem('Reporte de comisiones', Icons.payments_outlined),
  _NavItem('Bloqueos de agenda', Icons.event_busy_outlined),
  _NavItem('Inventario', Icons.inventory_2_outlined),
  _NavItem('Categorías de inventario', Icons.category_outlined),
  _NavItem('Proveedores', Icons.local_shipping_outlined),
  _NavItem('Compras y recepciones', Icons.shopping_cart_checkout_outlined),
  _NavItem('Movimientos de inventario', Icons.swap_horiz_outlined),
  _NavItem('Caja y ventas', Icons.point_of_sale_outlined),
  _NavItem('Sesiones de caja', Icons.pending_actions_outlined),
  _NavItem('Categorías de egresos', Icons.category_outlined),
  _NavItem('Movimientos de caja', Icons.swap_horiz_outlined),
  _NavItem('Cuentas bancarias', Icons.account_balance_outlined),
  _NavItem('Cuadres y arqueos', Icons.fact_check_outlined),
  _NavItem('Cajas registradoras', Icons.point_of_sale_outlined),

  _NavItem('Medios de pago', Icons.credit_card_outlined),
  _NavItem('Descuentos de lavados', Icons.local_offer_outlined),
  _NavItem('Cobros de lavados', Icons.payments_outlined),
  _NavItem('Sitio web', Icons.language_outlined),
  _NavItem('Mi Empresa', Icons.business_outlined),
  _NavItem('Configuración', Icons.settings_outlined),
  _NavItem('Pantallas de monitoreo', Icons.tv_outlined),
  _NavItem('Usuarios', Icons.manage_accounts_outlined),
  _NavItem('Smart POS', Icons.point_of_sale_outlined),
  _NavItem('Historial de ventas', Icons.receipt_long_outlined),
  _NavItem('Resumen de reportes', Icons.dashboard_outlined),
  _NavItem('Reporte de ventas', Icons.shopping_bag_outlined),
  _NavItem('Reporte de lavados', Icons.local_car_wash_outlined),
  _NavItem('Reporte de agenda', Icons.event_available_outlined),
  _NavItem('Reporte de caja', Icons.account_balance_wallet_outlined),
  _NavItem('Reporte de inventario', Icons.inventory_2_outlined),
  _NavItem('Reporte de clientes', Icons.people_outline),
  _NavItem('Reporte de personal', Icons.badge_outlined),
  _NavItem('Reporte fiscal', Icons.receipt_long_outlined),
  _NavItem('Reporte de compras', Icons.local_shipping_outlined),
  _NavItem('Diseñar comprobantes', Icons.design_services_outlined),
];

// ADN MyCarWash - Navegacion compacta 20.1.
class _CompactNavGroup {
  const _CompactNavGroup(this.label, this.icon, this.entries);
  final String label;
  final IconData icon;
  final List<String> entries;
}

const _compactNavGroups20_1 = <_CompactNavGroup>[
  _CompactNavGroup('Lavados', Icons.local_car_wash_outlined, [
    'Órdenes de lavado',
    'Cola de lavado',
    'Asignaciones',
    'Puestos de lavado',
    'Servicios',
    'Lavados',
  ]),
  _CompactNavGroup('Agenda y reservas', Icons.event_available_outlined, [
    'Reservas',
    'Bloqueos de agenda',
  ]),
  _CompactNavGroup('Clientes y vehículos', Icons.people_outline_rounded, [
    'Clientes',
    'Vehículos',
  ]),
  _CompactNavGroup('Personal', Icons.badge_outlined, [
    'Empleados',
    'Punto de asistencia QR',
    'Historial de asistencia',
    'Turnos de trabajo',
    'Asignaciones de turnos',
  ]),
  _CompactNavGroup('Inventario', Icons.inventory_2_outlined, [
    'Inventario',
    'Categorías de inventario',
    'Proveedores',
    'Compras y recepciones',
    'Movimientos de inventario',
  ]),
  _CompactNavGroup('Caja y bancos', Icons.account_balance_outlined, [
    'Caja y ventas',
    'Sesiones de caja',
    'Movimientos de caja',
    'Categorías de egresos',
    'Cuentas bancarias',
    'Cuadres y arqueos',
    'Cajas registradoras',
  ]),
  _CompactNavGroup('Ventas y cobros', Icons.payments_outlined, [
    'Smart POS',
    'Historial de ventas',
    'Cobros de lavados',
    'Medios de pago',
    'Descuentos de lavados',
    'Diseñar comprobantes',
  ]),
  _CompactNavGroup('Reportes', Icons.insights_outlined, [
    'Resumen de reportes',
    'Reporte de ventas',
    'Reporte de lavados',
    'Reporte de agenda',
    'Reporte de caja',
    'Reporte de inventario',
    'Reporte de clientes',
    'Reporte de personal',
    'Reporte mensual de asistencia',
    'Reporte de comisiones',
    'Reporte fiscal',
    'Reporte de compras',
  ]),
  _CompactNavGroup('Mi empresa', Icons.business_outlined, [
    'Mi Empresa',
    'Configuración',
    'Pantallas de monitoreo',
  ]),
  _CompactNavGroup('Usuarios', Icons.manage_accounts_outlined, ['Usuarios']),
  _CompactNavGroup('Sitio web', Icons.language_outlined, ['Sitio web']),
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
    if (!_navAllowed(selected)) {
      final allowed = List<int>.generate(
        _menu.length,
        (i) => i,
      ).where(_navAllowed).toList();
      if (allowed.isNotEmpty) selected = allowed.first;
    }
  }

  int selected = 0;
  int? _pendingWashOrderId;
  int _washPosSequence = 0;

  void _openWashInPos(Map<String, dynamic> order) {
    final washId = int.tryParse('${order['id']}');
    final posIndex = _menu.indexWhere((item) => item.title == 'Smart POS');
    if (washId == null || washId <= 0 || posIndex < 0) {
      return;
    }
    setState(() {
      _pendingWashOrderId = washId;
      _washPosSequence++;
      selected = posIndex;
    });
  }

  String? _expandedNavGroup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MediaQuery.sizeOf(context).width < 900
          ? AppBar(
              backgroundColor: AdnColors.sidebar,
              title: Text(_menu[selected].title),
              actions: [
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
            SizedBox(width: 232, child: _sidebar()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CompanyBillingAlerts24N8(),
                  if (MyCarWashSession.canNav('schedule', 'view'))
                    const CompanyBookingDailyStartup24D2(),
                  _mainContent(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Navegacion compacta, un grupo desplegado a la vez y submodulos originales.
  String _moduleFor(String destination) {
    if (destination == 'Dashboard') {
      return 'dashboard';
    }
    if (destination == 'Usuarios') {
      return 'users';
    }
    if (destination == 'Punto de asistencia QR') {
      return 'company';
    }
    if (destination == 'Mi Empresa' ||
        destination == 'Pantallas de monitoreo' ||
        destination == 'Configuración' ||
        destination == 'Sitio web') {
      return 'company';
    }
    if (destination == 'Historial de asistencia') return 'staff';
    if (destination.startsWith('Reporte') ||
        destination == 'Resumen de reportes') {
      return 'reports';
    }
    if (['Clientes', 'Vehículos'].contains(destination)) {
      return 'customers';
    }
    if ([
      'Empleados',
      'Turnos de trabajo',
      'Asignaciones de turnos',
    ].contains(destination)) {
      return 'staff';
    }
    if ([
      'Inventario',
      'Categorías de inventario',
      'Proveedores',
      'Compras y recepciones',
      'Movimientos de inventario',
    ].contains(destination)) {
      return 'inventory';
    }
    if (['Reservas', 'Bloqueos de agenda'].contains(destination)) {
      return 'schedule';
    }
    if ([
      'Caja y ventas',
      'Sesiones de caja',
      'Categorías de egresos',
      'Movimientos de caja',
      'Cuentas bancarias',
      'Cuadres y arqueos',
      'Cajas registradoras',
    ].contains(destination)) {
      return 'cash';
    }
    if ([
      'Smart POS',
      'Historial de ventas',
      'Cobros de lavados',
      'Medios de pago',
      'Descuentos de lavados',
      'Diseñar comprobantes',
    ].contains(destination)) {
      return 'sales';
    }
    return 'washes';
  }

  bool _navAllowed(int index) => MyCarWashSession.canNav(
    _moduleFor(_menu[index].title),
    _menu[index].title == 'Punto de asistencia QR' ? 'edit' : 'view',
  );

  Widget _buildCompactNavigation() {
    final known = <String>{'Dashboard'};
    for (final group in _compactNavGroups20_1) {
      known.addAll(group.entries);
    }
    final extra = <int>[
      for (var index = 1; index < _menu.length; index++)
        if (!known.contains(_menu[index].title) && _navAllowed(index)) index,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 10),
      children: [
        if (_navAllowed(0)) _compactNavEntry(0),
        const SizedBox(height: 8),
        for (final group in _compactNavGroups20_1) _compactNavSection(group),
        for (final index in extra) _compactNavEntry(index),
      ],
    );
  }

  Widget _compactNavSection(_CompactNavGroup group) {
    final indices = <int>[
      for (final title in group.entries)
        _menu.indexWhere((item) => item.title == title),
    ].where((index) => index >= 0 && _navAllowed(index)).toList();
    if (indices.isEmpty) return const SizedBox.shrink();
    final expanded = _expandedNavGroup == group.label;
    final containsActive = indices.contains(selected);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() {
                _expandedNavGroup = expanded ? null : group.label;
              }),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: containsActive
                      ? AdnColors.turquoise.withValues(alpha: 0.10)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      group.icon,
                      size: 18,
                      color: containsActive || expanded
                          ? AdnColors.turquoiseLight
                          : AdnColors.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        group.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: containsActive || expanded
                              ? AdnColors.white
                              : AdnColors.muted,
                          fontWeight: containsActive || expanded
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: AdnColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 2, bottom: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final index in indices)
                    _compactNavEntry(index, nested: true),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactNavEntry(int index, {bool nested = false}) {
    final item = _menu[index];
    final active = selected == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('menu_${item.title}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => selected = index);
            if (MediaQuery.sizeOf(context).width < 900) {
              Navigator.of(context).pop();
            }
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: EdgeInsets.symmetric(
              horizontal: nested ? 8 : 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: active
                  ? AdnColors.turquoise.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: active
                  ? Border(
                      left: BorderSide(color: AdnColors.turquoise, width: 2),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: nested ? 15 : 18,
                  color: active ? AdnColors.turquoiseLight : AdnColors.muted,
                ),
                SizedBox(width: nested ? 9 : 10),
                Expanded(
                  child: Text(
                    item.title == 'Lavados' && nested
                        ? 'Vista general de lavados'
                        : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: active ? AdnColors.white : AdnColors.muted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
                Expanded(
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
          Divider(color: AdnColors.border, height: 1),
          const SizedBox(height: 16),
          Expanded(child: _buildCompactNavigation()),
          Divider(color: AdnColors.border, height: 1),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Cerrar sesión'),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(15, 0, 15, 16),
            child: Text(
              'PANEL ADMINISTRATIVO',
              style: TextStyle(fontSize: 10, color: AdnColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainContent() {
    final destination = _menu[selected].title;
    if (destination == 'Caja y ventas' ||
        destination == 'Cuentas bancarias' ||
        destination == 'Cuadres y arqueos') {
      return CompanyFinanceHub24K(
        key: ValueKey<String>('finance24k_$destination'),
        section: destination == 'Cuentas bancarias'
            ? 'banks'
            : destination == 'Cuadres y arqueos'
            ? 'reconciliations'
            : 'cash',
        onNavigate: (target) {
          final index = _menu.indexWhere((item) => item.title == target);
          if (index >= 0 && mounted) {
            setState(() => selected = index);
          }
        },
      );
    }
    if (destination == 'Punto de asistencia QR') {
      return const CompanyAttendanceStation24N4();
    }
    if (destination == 'Historial de asistencia') {
      return const CompanyAttendanceReportsB25D(monthlyReport: false);
    }
    if (destination == 'Reporte de comisiones') {
      return const CompanyCommissionReportB25L();
    }
    if (destination == 'Reporte mensual de asistencia') {
      return const CompanyAttendanceReportsB25D(monthlyReport: true);
    }
    if (destination == 'Asignaciones de turnos') {
      return const CompanyRosterBulkB25D();
    }
    if (destination == 'Dashboard') {
      return CompanyDashboard24APage(
        onNavigate: (target) {
          final index = _menu.indexWhere((item) => item.title == target);
          if (index >= 0) setState(() => selected = index);
        },
      );
    }
    if (destination == 'Resumen de reportes') {
      return const CompanyUnifiedReportsPage(kind: 'overview');
    }
    if (destination == 'Reporte de ventas') {
      return const CompanyUnifiedReportsPage(kind: 'pos');
    }
    if (destination == 'Reporte de lavados') {
      return const CompanyUnifiedReportsPage(kind: 'washes');
    }
    if (destination == 'Reporte de agenda') {
      return const CompanyUnifiedReportsPage(kind: 'bookings');
    }
    if (destination == 'Reporte de caja') {
      return const CompanyUnifiedReportsPage(kind: 'cash');
    }
    if (destination == 'Reporte de inventario') {
      return const CompanyUnifiedReportsPage(kind: 'inventory');
    }
    if (destination == 'Reporte de clientes') {
      return const CompanyUnifiedReportsPage(kind: 'customers');
    }
    if (destination == 'Reporte de personal') {
      return const CompanyUnifiedReportsPage(kind: 'staff');
    }
    if (destination == 'Reporte fiscal') {
      return const CompanyUnifiedReportsPage(kind: 'fiscal');
    }
    if (destination == 'Compras y recepciones') {
      return const CompanyPurchasingPage();
    }
    if (destination == 'Reporte de compras') {
      return const CompanyUnifiedReportsPage(kind: 'purchases');
    }
    if (destination == 'Reportes Smart POS') {
      return const CompanyPosReportsPage();
    }
    if (destination == 'Diseñar comprobantes') {
      return const CompanyPosDesignerPage();
    }
    if (destination == 'Smart POS' || destination == 'Historial de ventas') {
      return CompanySmartPosPage(
        key: ValueKey<String>(
          'pos_${destination}_${_pendingWashOrderId ?? 0}_$_washPosSequence',
        ),
        initialHistory: destination == 'Historial de ventas',
        initialWashOrderId: destination == 'Smart POS'
            ? _pendingWashOrderId
            : null,
        onWashSaleCompleted: () {
          if (mounted) {
            setState(() => _pendingWashOrderId = null);
          }
        },
      );
    }
    if (destination == 'Mi Empresa') {
      return const CompanySettingsPage(key: ValueKey<String>('company_my_business_page'));
    }
    if (destination == 'Configuración') {
      return const CompanySettingsPage(
        key: ValueKey<String>('company_configuration_page'),
        configurationOnly: true,
        initialSection: 2,
      );
    }
    if (destination == 'Pantallas de monitoreo') {
      return const CompanyMonitorDevicesRpi01gPage();
    }
    if (destination == 'Usuarios') {
      return const CompanyUsers24N2Page();
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
    final salesModule = switch (_menu[selected].title) {
      'Cuentas bancarias' => SalesModule.banks,
      'Medios de pago' => SalesModule.methods,
      'Descuentos de lavados' => SalesModule.discounts,
      'Cobros de lavados' => SalesModule.payments,
      _ => null,
    };
    if (salesModule != null) {
      return CompanySalesPage(module: salesModule);
    }
    final cashModule = switch (_menu[selected].title) {
      'Caja y ventas' => CashModule.registers,
      'Cajas registradoras' => CashModule.registers,
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
    if (_menu[selected].title == 'Lavados') {
      return const CompanyWashMonitor24B1();
    }
    final washModule = switch (_menu[selected].title) {
      'Puestos de lavado' => WashModule.bays,
      'Órdenes de lavado' => WashModule.orders,
      'Asignaciones' => WashModule.assignments,
      'Cola de lavado' => WashModule.queue,
      _ => null,
    };
    if (washModule != null) {
      return CompanyWashWorkflowPage(
        module: washModule,
        onCheckoutInPos: _openWashInPos,
      );
    }
    final isHome = selected == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _Eyebrow(text: 'ADN PUBLICIDAD · SOFTWARE')),
            Icon(Icons.shield_outlined, color: AdnColors.turquoise),
            const SizedBox(width: 8),
            Text(
              'Vista previa',
              style: TextStyle(fontSize: 12, color: AdnColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          isHome ? 'Resumen general' : _menu[selected].title,
          style: TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w800,
            color: AdnColors.white,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
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
                        Text(
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
            child: Padding(
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
            Text(label, style: TextStyle(color: AdnColors.muted)),
          ],
        ),
      ),
    ),
  );
}
