<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use DateTimeImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/** Bloque 22B: informes de lectura, aislados por empresa y fecha. No escribe datos. */
final class CompanyUnifiedReportsController extends Controller
{
    private const TITLES = [
        'overview' => 'Resumen general',
        'pos' => 'Ventas Smart POS',
        'washes' => 'Lavados y servicios',
        'bookings' => 'Agenda y reservas',
        'cash' => 'Caja y cobros',
        'inventory' => 'Inventario y productos',
        'customers' => 'Clientes y vehículos',
        'staff' => 'Personal y asignaciones',
        'fiscal' => 'Comprobantes e ISV',
        'purchases' => 'Proveedores y entradas',
    ];

    private function authorizeCompany(Request $request, int $company): void
    {
        $uid = (int) $request->user()->id;
        if (!DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $uid)
            ->where('p.code', 'company.view')->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente para reportes.');
    }

    private function has(string $table, string $column = 'id'): bool
    {
        return Schema::hasTable($table) && Schema::hasColumn($table, $column);
    }

    private function filtered(string $table, int $company, ?int $branch, string $from, string $until, string $date = 'created_at')
    {
        if (!$this->has($table, 'company_id') || !$this->has($table, $date)) return null;
        $q = DB::table($table)->where('company_id', $company)
            ->where($date, '>=', $from.' 00:00:00')->where($date, '<', $until);
        if ($this->has($table, 'deleted_at')) $q->whereNull('deleted_at');
        if ($branch !== null) {
            if (!$this->has($table, 'branch_id')) return null; // Nunca filtrar incorrectamente.
            $q->where('branch_id', $branch);
        }
        return $q;
    }

    private function washPaymentsFiltered(int $company, ?int $branch, string $from, string $until)
    {
        $q = $this->filtered('wash_order_payments', $company, null, $from, $until, 'posted_at');
        if (!$q) return null;
        if ($branch !== null) {
            if (!$this->has('wash_orders', 'branch_id')) return null;
            $q->whereIn('order_id', function ($sub) use ($company, $branch): void {
                $sub->select('id')->from('wash_orders')->where('company_id', $company)->where('branch_id', $branch);
            });
        }
        return $q;
    }

    private function cashFiltered(int $company, ?int $branch, string $from, string $until)
    {
        if (!$this->has('cash_movements', 'created_at') || !$this->has('cash_sessions', 'register_id')
            || !$this->has('cash_registers', 'branch_id')) return null;
        $q = DB::table('cash_movements as m')
            ->join('cash_sessions as s', function ($j): void {
                $j->on('s.id', '=', 'm.session_id')->on('s.company_id', '=', 'm.company_id');
            })
            ->join('cash_registers as r', function ($j): void {
                $j->on('r.id', '=', 's.register_id')->on('r.company_id', '=', 'm.company_id');
            })
            ->where('m.company_id', $company)->where('m.created_at', '>=', $from.' 00:00:00')
            ->where('m.created_at', '<', $until);
        if ($this->has('cash_movements', 'deleted_at')) $q->whereNull('m.deleted_at');
        if ($branch !== null) $q->where('r.branch_id', $branch);
        return $q;
    }

    private function metric(string $label, mixed $value, string $unit = ''): array
    {
        return ['label' => $label, 'value' => $unit === 'HNL' ? 'L '.number_format((float) $value, 2, '.', ',') : (string) $value];
    }

    private function section(string $name, array $columns, iterable $rows, string $note = ''): array
    {
        $list = [];
        foreach ($rows as $row) {
            $a = (array) $row;
            $out = [];
            foreach ($columns as $key => $label) $out[$key] = (string) ($a[$key] ?? '');
            $list[] = $out;
        }
        return ['title' => $name, 'columns' => $columns, 'rows' => $list, 'note' => $note];
    }

    private function unavailable(array &$warnings, string $source): void
    {
        $warnings[] = 'La fuente de '.$source.' no está disponible con el esquema actual o no admite filtro por sucursal.';
    }


    /** Identidad corporativa desde datos verificados de la empresa y plantillas publicadas.
     *  El logo es propio de la sucursal/negocio; ADN no aparece en el encabezado.
     */
    private function companyIdentity(int $company, ?int $branch, array &$warnings): array
    {
        $row = DB::table('companies')->where('id', $company)->first();
        $info = [
            'name' => (string) ($row->name ?? 'Empresa'),
            'legal_name' => '', 'rtn' => '', 'address' => '',
            'phone' => '', 'email' => '', 'website' => '',
            'logo_base64' => '', 'branch_name' => 'Todas las sucursales',
        ];
        foreach (['legal_name','rtn','address','phone','email','website'] as $field) {
            if ($this->has('companies', $field)) {
                $info[$field] = (string) ($row?->{$field} ?? '');
            }
        }
        if ($branch !== null) {
            $branchRow = DB::table('branches')->where('company_id',$company)->where('id',$branch)->first();
            $info['branch_name'] = (string) ($branchRow->name ?? 'Sucursal');
            if ($this->has('branches','address') && $info['address'] === '') {
                $info['address'] = (string) ($branchRow->address ?? '');
            }
        }
        if ($this->has('pos_fiscal_authorizations','legal_name') && $branch !== null) {
            $f = DB::table('pos_fiscal_authorizations')->where('company_id',$company)
                ->where('branch_id',$branch)->where('is_active',true)->orderByDesc('id')->first();
            if ($f) {
                if ($info['legal_name'] === '') $info['legal_name'] = (string) ($f->legal_name ?? '');
                if ($info['rtn'] === '') $info['rtn'] = (string) ($f->rtn ?? '');
            }
        }
        if ($this->has('companies','logo_base64') && $row && is_string($row->logo_base64 ?? null)) {
            $info['logo_base64'] = (string) $row->logo_base64;
        }
        if ($info['logo_base64'] === '' && $this->has('pos_document_template_revisions','design_json')) {
            $templates = DB::table('pos_document_template_revisions')->where('company_id',$company);
            if ($branch !== null) $templates->where('branch_id',$branch);
            foreach ($templates->orderByDesc('id')->limit(30)->get(['design_json']) as $tpl) {
                $design = json_decode((string) $tpl->design_json,true);
                if (is_array($design) && is_string($design['logo_base64'] ?? null)
                    && $design['logo_base64'] !== '') {
                    $info['logo_base64'] = $design['logo_base64'];
                    break;
                }
            }
        }
        // Sólo PNG/JPEG reales y hasta 1MB de bytes; nunca archivos arbitrarios.
        $encoded = $info['logo_base64'];
        if ($encoded !== '') {
            $bytes = strlen($encoded) <= 1398108 ? base64_decode($encoded, true) : false;
            $image = $bytes !== false && strlen($bytes) <= 1048576 ? @getimagesizefromstring($bytes) : false;
            if (!$image || !in_array((int) ($image[2] ?? 0), [IMAGETYPE_JPEG,IMAGETYPE_PNG], true)) {
                $info['logo_base64'] = '';
                $warnings[] = 'El logotipo almacenado es inválido para el PDF; configura un PNG/JPG válido.';
            }
        } else {
            $warnings[] = 'No hay logotipo corporativo configurado para el encabezado. Configúralo en el diseñador de comprobantes.';
        }
        return $info;
    }

    public function show(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company);
        $input = $request->validate([
            'kind' => ['required', 'string', 'in:'.implode(',', array_keys(self::TITLES))],
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d'],
            'branch_id' => ['sometimes', 'integer', 'min:1'],
        ]);
        $from = (string) $input['from'];
        $to = (string) $input['to'];
        $start = DateTimeImmutable::createFromFormat('!Y-m-d', $from);
        $end = DateTimeImmutable::createFromFormat('!Y-m-d', $to);
        if (!$start || !$end || $start > $end || $start->diff($end)->days > 365) {
            throw ValidationException::withMessages(['from' => 'Selecciona un período válido de hasta 366 días.']);
        }
        $until = $end->modify('+1 day')->format('Y-m-d').' 00:00:00';
        $branch = isset($input['branch_id']) ? (int) $input['branch_id'] : null;
        if ($branch !== null && !DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'La sucursal no pertenece a esta empresa.']);
        }
        $kind = (string) $input['kind'];
        $warnings = [];
        $metrics = [];
        $sections = [];
        $scope = ['company_id' => $company, 'branch_id' => $branch, 'from' => $from, 'to' => $to, 'currency' => 'HNL'];
        $pos = null;
        if (in_array($kind, ['pos', 'fiscal', 'overview', 'cash'], true)) {
            $original = app(CompanyPosReportsController::class)->summary($request, $company)->getData(true);
            $pos = $original['data'];
        }

        if ($kind === 'pos' || $kind === 'overview') {
            $k = $pos['kpis'];
            $metrics[] = $this->metric('Ventas POS confirmadas', $k['sales_count']);
            $metrics[] = $this->metric('Ingresos POS', $k['total'], 'HNL');
            $metrics[] = $this->metric('Descuentos POS', $k['discounts'], 'HNL');
            $metrics[] = $this->metric('ISV registrado POS', $k['tax'], 'HNL');
            $sections[] = $this->section('Ventas POS por día', ['day' => 'Fecha', 'sales_count' => 'Ventas', 'total' => 'Total HNL'], $pos['daily']);
            $sections[] = $this->section('Cobros POS por canal', ['channel' => 'Canal', 'payment_count' => 'Pagos', 'amount' => 'Importe HNL'], $pos['payment_channels'], 'Una venta mixta se cuenta una vez; sus pagos se desglosan por separado.');
            if ($kind === 'pos') {
                $sections[] = $this->section('Artículos más vendidos', ['sku' => 'SKU', 'name' => 'Artículo', 'quantity' => 'Cantidad', 'gross_line_amount' => 'Líneas HNL'], $pos['top_products']);
            }
        }
        if ($kind === 'fiscal') {
            $k = $pos['kpis'];
            $metrics[] = $this->metric('ISV POS registrado', $k['tax'], 'HNL');
            $metrics[] = $this->metric('Ventas POS', $k['sales_count']);
            $sections[] = $this->section('Facturas y recibos emitidos', ['document_type' => 'Documento', 'sales_count' => 'Cantidad', 'total' => 'Importe HNL'], $pos['documents']);
            $sections[] = $this->section('Ventas por día', ['day' => 'Fecha', 'sales_count' => 'Ventas', 'total' => 'Total HNL'], $pos['daily']);
            $warnings[] = 'Reporte interno del POS: no certifica validez de CAI, declaraciones tributarias ni retenciones externas.';
        }
        if (in_array($kind, ['washes', 'overview'], true)) {
            $q = $this->filtered('wash_orders', $company, $branch, $from, $until);
            if ($q) {
                $metrics[] = $this->metric('Órdenes de lavado creadas', (clone $q)->count());
                if ($this->has('wash_orders', 'status')) {
                    $rows = (clone $q)->select('status')->selectRaw('COUNT(*) AS total')->groupBy('status')->orderBy('status')->get();
                    $sections[] = $this->section('Lavados por estado', ['status' => 'Estado', 'total' => 'Órdenes'], $rows);
                }
                if ($this->has('wash_orders', 'quoted_price') && $kind === 'washes') {
                    $metrics[] = $this->metric('Valor cotizado de órdenes creadas', (clone $q)->sum('quoted_price'), 'HNL');
                    $warnings[] = 'El valor cotizado no equivale a dinero cobrado ni a ganancia.';
                }
            } else $this->unavailable($warnings, 'órdenes de lavado');
            $p = $this->washPaymentsFiltered($company, $branch, $from, $until);
            if ($p && $this->has('wash_order_payments', 'status') && $this->has('wash_order_payments','amount')) {
                $p->where('status', 'POSTED');
                $metrics[] = $this->metric('Cobros de lavados registrados', (clone $p)->sum('amount'), 'HNL');
                if ($kind === 'washes') {
                    $rows = (clone $p)->selectRaw('DATE(posted_at) AS day')->selectRaw('COUNT(*) AS payments_count')
                        ->selectRaw('COALESCE(SUM(amount),0) AS total')->groupByRaw('DATE(posted_at)')->orderBy('day')->get();
                    $sections[] = $this->section('Cobros de lavados por día', ['day'=>'Fecha','payments_count'=>'Movimientos','total'=>'Total HNL'], $rows, 'Se cuentan cobros confirmados; múltiples pagos de una orden son movimientos distintos.');
                }
            } else $this->unavailable($warnings, 'cobros de lavados por sucursal');
        }
        if ($kind === 'bookings' || $kind === 'overview') {
            $table = $this->has('bookings', 'created_at') ? 'bookings' : ($this->has('appointments', 'created_at') ? 'appointments' : '');
            $q = $table !== '' ? $this->filtered($table, $company, $branch, $from, $until) : null;
            if ($q) {
                $metrics[] = $this->metric('Reservas creadas', (clone $q)->count());
                if ($this->has($table, 'status')) {
                    $rows = (clone $q)->select('status')->selectRaw('COUNT(*) AS total')->groupBy('status')->orderBy('status')->get();
                    $sections[] = $this->section('Reservas por estado', ['status'=>'Estado','total'=>'Cantidad'], $rows);
                }
                $warnings[] = 'Las fechas filtran la creación de la reserva, no necesariamente la fecha del servicio.';
            } else $this->unavailable($warnings, 'agenda y reservas');
        }
        if ($kind === 'cash' || $kind === 'overview') {
            if ($kind === 'cash' && $pos) {
                $sections[] = $this->section('Cobros del Smart POS por canal',
                    ['channel'=>'Canal','payment_count'=>'Pagos','amount'=>'Importe HNL'],
                    $pos['payment_channels'],
                    'Este desglose ya está reflejado en los movimientos correspondientes; no volver a sumar para calcular ingresos.');
            }
            $q = $this->cashFiltered($company, $branch, $from, $until);
            if ($q && $this->has('cash_movements', 'direction') && $this->has('cash_movements', 'amount')) {
                $rows = (clone $q)->select('m.direction')->selectRaw('COUNT(*) AS movements')
                    ->selectRaw('COALESCE(SUM(m.amount),0) AS total')
                    ->groupBy('m.direction')->orderBy('m.direction')->get();
                $sections[] = $this->section('Movimientos de caja', ['direction'=>'Dirección','movements'=>'Movimientos','total'=>'Importe HNL'], $rows, 'Incluye movimientos de caja registrados; no sumar de nuevo a cobros POS.');
                if ($kind === 'cash') $metrics[] = $this->metric('Movimientos de caja', (clone $q)->count());
            } else $this->unavailable($warnings, 'movimientos de caja');
            if ($kind === 'cash') {
                $p = $this->washPaymentsFiltered($company, $branch, $from, $until);
                if ($p && $this->has('wash_order_payments', 'status') && $this->has('wash_order_payments','amount')) {
                    $rows = (clone $p)->where('status','POSTED')->select('payment_method_id')
                        ->selectRaw('COUNT(*) AS movements')->selectRaw('COALESCE(SUM(amount),0) AS total')
                        ->groupBy('payment_method_id')->orderBy('payment_method_id')->get();
                    $sections[] = $this->section('Cobros de lavados por medio', ['payment_method_id'=>'Medio ID','movements'=>'Pagos','total'=>'Importe HNL'], $rows);
                }
            }
        }
        if ($kind === 'inventory' || $kind === 'purchases' || $kind === 'overview') {
            $q = $this->filtered('inventory_movements', $company, $branch, $from, $until);
            if ($q && $this->has('inventory_movements', 'movement_type') && $this->has('inventory_movements', 'quantity')) {
                $rows = (clone $q)->select('movement_type')->selectRaw('COUNT(*) AS movements')
                    ->selectRaw('COALESCE(SUM(quantity),0) AS quantity')
                    ->groupBy('movement_type')->orderBy('movement_type')->get();
                $sections[] = $this->section('Movimientos de inventario', ['movement_type'=>'Tipo','movements'=>'Registros','quantity'=>'Cantidad'], $rows, 'Entradas, salidas y ajustes en el período, sin inferir ventas o compras a partir de todos los movimientos.');
                if ($kind !== 'overview') $metrics[] = $this->metric('Movimientos registrados', (clone $q)->count());
            } else $this->unavailable($warnings, 'inventario por fechas');
            if ($kind === 'inventory' && $this->has('inventory_items', 'company_id')) {
                $items = DB::table('inventory_items')->where('company_id', $company);
                if ($this->has('inventory_items', 'deleted_at')) $items->whereNull('deleted_at');
                $metrics[] = $this->metric('Artículos del catálogo empresarial', $items->count());
                $warnings[] = 'El catálogo es compartido por empresa; el conteo de artículos no se limita por sucursal o fecha.';
            }
        }
        if ($kind === 'customers') {
            foreach (['clients' => 'Clientes creados', 'vehicles' => 'Vehículos registrados'] as $table => $label) {
                $q = $this->filtered($table, $company, null, $from, $until);
                if ($q) {
                    $metrics[] = $this->metric($label, (clone $q)->count());
                    $rows = (clone $q)->selectRaw('DATE(created_at) AS day')
                        ->selectRaw('COUNT(*) AS total')->groupByRaw('DATE(created_at)')->orderBy('day')->get();
                    $sections[] = $this->section($label.' por fecha', ['day'=>'Fecha','total'=>'Cantidad'], $rows);
                } else $this->unavailable($warnings, $label);
            }
            $warnings[] = 'Clientes y vehículos pertenecen a la empresa; la selección de sucursal no aplica a estos catálogos.';
        }
        if ($kind === 'staff') {
            $q = $this->filtered('employees', $company, null, $from, $until);
            if ($q) {
                $metrics[] = $this->metric('Empleados registrados en el período', (clone $q)->count());
                $rows = (clone $q)->selectRaw('DATE(created_at) AS day')->selectRaw('COUNT(*) AS total')
                    ->groupByRaw('DATE(created_at)')->orderBy('day')->get();
                $sections[] = $this->section('Altas de empleados', ['day'=>'Fecha','total'=>'Cantidad'], $rows);
            } else $this->unavailable($warnings, 'personal');
            $p = $this->filtered('wash_assignments', $company, $branch, $from, $until);
            if ($p) {
                $metrics[] = $this->metric('Asignaciones de lavadores', (clone $p)->count());
                $warnings[] = 'Asignaciones no equivalen a lavados únicos ni al rendimiento individual.';
            } else $this->unavailable($warnings, 'asignaciones por sucursal');
        }
        if ($kind === 'purchases') {
            $q = $this->filtered('inventory_suppliers', $company, null, $from, $until);
            if ($q) $metrics[] = $this->metric('Proveedores registrados', (clone $q)->count());
            else $this->unavailable($warnings, 'proveedores');
            $warnings[] = 'No se informa costo de compras ni órdenes recibidas sin registros de compras verificados. Entradas de inventario no equivalen necesariamente a compras.';
        }
        if ($kind === 'overview') $warnings[] = 'Los totales POS, de lavados y caja son conceptos distintos; no deben sumarse entre sí. Resumen operativo, no balance contable.';
        if (count($sections) === 0 && count($metrics) === 0) $warnings[] = 'Sin datos verificables para este reporte y período.';
        $identity = $this->companyIdentity($company, $branch, $warnings);
        return response()->json(['data' => [
            'kind' => $kind, 'title' => self::TITLES[$kind], 'scope' => $scope,
            'metrics' => $metrics, 'sections' => $sections, 'warnings' => $warnings,
            'company' => $identity,
            'generated_at' => now()->toIso8601String(),
        ]]);
    }
}
