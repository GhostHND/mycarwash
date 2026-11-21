<?php

namespace App\Http\Controllers\Api\V1;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** B25J-FIX2: ingresos cobrados (POS completo + pagos de lavado no duplicados),
 * comisiones verificadas por asistencia, y egresos de caja. Solo lectura.
 */
final class CompanyDashboardFinanceB25J
{
    private static function has(string $table, array $columns): bool
    {
        if (!Schema::hasTable($table)) return false;
        foreach ($columns as $column) {
            if (!Schema::hasColumn($table, $column)) return false;
        }
        return true;
    }

    private static function cents(mixed $value): int
    {
        return (int) round(((float) $value) * 100);
    }

    private static function money(int $cents): string
    {
        return number_format($cents / 100, 2, '.', '');
    }

    /** Retorna importes solo cuando las fuentes de datos existen. */
    public static function summary(int $company, ?int $branch, string $timezone): array
    {
        // La zona operativa predeterminada siempre es Honduras; UTC se usa solo al persistir.
        if (!in_array($timezone, timezone_identifiers_list(), true) || $timezone === 'UTC') {
            $timezone = 'America/Tegucigalpa';
        }
        $today = now($timezone)->toDateString();
        $days = [];
        for ($offset = 6; $offset >= 0; $offset--) {
            $day = now($timezone)->subDays($offset)->toDateString();
            $days[$day] = ['date' => $day, 'services' => null, 'expenses' => null, 'commissions' => null];
        }
        $first = Carbon::parse(array_key_first($days), $timezone)->startOfDay()->utc()->format('Y-m-d H:i:s');
        $end = now($timezone)->addDay()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $issues = [];
        $paid = [];
        $hasPayments = self::has('wash_order_payments', ['company_id', 'order_id', 'status', 'posted_at', 'amount', 'deleted_at']);
        $hasPos = self::has('pos_sales', ['company_id', 'branch_id', 'wash_order_id', 'total', 'status', 'posted_at']);
        $hasOrders = self::has('wash_orders', ['id', 'company_id', 'branch_id', 'status', 'completed_at', 'delivered_at']);

        // La tarjeta «Servicios» representa TODOS los ingresos efectivamente registrados:
        // ventas POS (incluidos artículos) y pagos de lavado que no estén reflejados
        // en una venta POS vinculada. La vinculación se revisa sin filtro de fecha
        // para impedir que un mismo lavado se cuente en dos días distintos.
        if ($hasPos || ($hasOrders && $hasPayments)) {
            foreach ($days as &$entry) $entry['services'] = 0.0;
            unset($entry);

            if ($hasPos) {
                $posQuery = DB::table('pos_sales as s')
                    ->where('s.company_id', $company)
                    ->where('s.status', 'POSTED')
                    ->where('s.posted_at', '>=', $first)
                    ->where('s.posted_at', '<', $end);
                if ($branch !== null) $posQuery->where('s.branch_id', $branch);
                foreach ($posQuery->get(['s.wash_order_id', 's.posted_at', 's.total']) as $item) {
                    $day = Carbon::parse($item->posted_at, 'UTC')->setTimezone($timezone)->toDateString();
                    if (!isset($days[$day])) continue;
                    $days[$day]['services'] += (float) $item->total;
                    if ($item->wash_order_id !== null) {
                        $paid[(int) $item->wash_order_id][$day] = true;
                    }
                }
            }

            if ($hasPayments && $hasOrders) {
                $query = DB::table('wash_order_payments as p')
                    ->join('wash_orders as o', function ($join): void {
                        $join->on('o.id', '=', 'p.order_id')->on('o.company_id', '=', 'p.company_id');
                    })
                    ->where('p.company_id', $company)
                    ->where('p.status', 'POSTED')
                    ->whereNull('p.deleted_at')
                    ->where('p.posted_at', '>=', $first)
                    ->where('p.posted_at', '<', $end);
                if ($branch !== null) $query->where('o.branch_id', $branch);
                $washPayments = $query->get(['p.order_id', 'p.posted_at', 'p.amount']);
                $orderIds = $washPayments->pluck('order_id')->unique()->values()->all();
                $coveredByPos = [];
                if ($hasPos && $orderIds) {
                    $coveredByPos = DB::table('pos_sales')
                        ->where('company_id', $company)
                        ->where('status', 'POSTED')
                        ->whereIn('wash_order_id', $orderIds)
                        ->whereNotNull('wash_order_id')
                        ->pluck('wash_order_id')->map(fn ($id) => (int) $id)->all();
                }
                foreach ($washPayments as $item) {
                    $order = (int) $item->order_id;
                    if (in_array($order, $coveredByPos, true)) continue;
                    $day = Carbon::parse($item->posted_at, 'UTC')->setTimezone($timezone)->toDateString();
                    if (!isset($days[$day])) continue;
                    $days[$day]['services'] += (float) $item->amount;
                    $paid[$order][$day] = true;
                }
            }
        } else {
            $issues[] = 'No se pudo verificar ninguna fuente de ingresos cobrados.';
        }

        $expensesAvailable = self::has('cash_movements', ['company_id','session_id','direction','amount','created_at','deleted_at','expense_category_id'])
            && self::has('cash_sessions', ['company_id','register_id'])
            && self::has('cash_registers', ['company_id','branch_id']);
        if ($expensesAvailable) {
            foreach ($days as &$entry) $entry['expenses'] = 0.0;
            unset($entry);
            $query = DB::table('cash_movements as m')
                ->join('cash_sessions as s', function ($join): void {
                    $join->on('s.id', '=', 'm.session_id')->on('s.company_id', '=', 'm.company_id');
                })
                ->join('cash_registers as r', function ($join): void {
                    $join->on('r.id', '=', 's.register_id')->on('r.company_id', '=', 'm.company_id');
                })->where('m.company_id', $company)->where('m.direction', 'OUT')
                ->whereNotNull('m.expense_category_id')->whereNull('m.deleted_at')
                ->where('m.created_at', '>=', $first)->where('m.created_at', '<', $end);
            if ($branch !== null) $query->where('r.branch_id', $branch);
            foreach ($query->get(['m.created_at','m.amount']) as $item) {
                $day = Carbon::parse($item->created_at, 'UTC')->setTimezone($timezone)->toDateString();
                if (isset($days[$day])) $days[$day]['expenses'] += (float) $item->amount;
            }
        } else $issues[] = 'No se pudieron verificar los egresos categorizados.';

        // La producción corresponde a servicios FINALIZADOS, no al día del cobro.
        // Una comisión solo existe cuando el lavador tiene entrada de asistencia
        // en la fecha local de finalización. No se crean comisiones ficticias.
        $production = [];
        $commissionsAvailable = self::has('wash_order_service_lines_b25',
                ['company_id','order_id','commission_employee_id','commission_amount','commission_percent','price'])
            && self::has('washer_attendance_24n3', ['company_id','employee_id','work_date','check_in_at'])
            && self::has('employees', ['id','company_id','full_name']);
        if ($commissionsAvailable && $hasOrders) {
            foreach ($days as &$entry) $entry['commissions'] = 0.0;
            unset($entry);
            // completed_at es la fuente principal de la fecha del trabajo; al entregar
            // directamente se permite delivered_at si completed_at no fue registrado.
            $ordersQuery = DB::table('wash_orders')->where('company_id', $company)
                ->whereIn('status', ['TERMINADO', 'ENTREGADO'])
                ->whereRaw('COALESCE(completed_at, delivered_at) >= ?', [$first])
                ->whereRaw('COALESCE(completed_at, delivered_at) < ?', [$end]);
            if ($branch !== null) $ordersQuery->where('branch_id', $branch);
            $orders = $ordersQuery->get(['id','completed_at','delivered_at']);
            $orderDates = [];
            $workTimes = [];
            foreach ($orders as $order) {
                $stamp = $order->completed_at ?? $order->delivered_at;
                if ($stamp === null) continue;
                $atUtc = Carbon::parse($stamp, 'UTC');
                $localDate = $atUtc->copy()->setTimezone($timezone)->toDateString();
                if (!isset($days[$localDate])) continue;
                $orderDates[(int)$order->id] = $localDate;
                $workTimes[(int)$order->id] = $atUtc;
            }
            if ($orderDates) {
                $lines = DB::table('wash_order_service_lines_b25 as l')
                    ->where('l.company_id', $company)
                    ->whereIn('l.order_id', array_keys($orderDates))
                    ->orderBy('l.order_id')->orderBy('l.line_order')->orderBy('l.id')
                    ->get(['l.id','l.order_id','l.commission_employee_id',
                        'l.commission_amount','l.commission_percent','l.price']);

                // Compatibilidad con órdenes donde el lavador fue asignado
                // después de crear la orden: primer empleado asignado.
                $primaryByOrder = [];
                if (self::has('wash_assignments',
                    ['company_id','order_id','employee_id','assigned_at','id'])) {
                    $assignments = DB::table('wash_assignments')
                        ->where('company_id', $company)
                        ->whereIn('order_id', array_keys($orderDates))
                        ->orderBy('order_id')->orderBy('assigned_at')->orderBy('id')
                        ->get(['order_id','employee_id']);
                    foreach ($assignments as $a) {
                        $id = (int) $a->order_id;
                        if (!isset($primaryByOrder[$id])) {
                            $primaryByOrder[$id] = (int) $a->employee_id;
                        }
                    }
                }
                $employeeIds = [];
                foreach ($lines as $line) {
                    $employee = $primaryByOrder[(int)$line->order_id]
                        ?? ($line->commission_employee_id !== null
                            ? (int)$line->commission_employee_id : null);
                    if ($employee !== null) $employeeIds[$employee] = true;
                }
                if ($employeeIds) {
                    $names = DB::table('employees')
                        ->where('company_id', $company)
                        ->whereIn('id', array_keys($employeeIds))
                        ->pluck('full_name', 'id')->all();
                    // Una asistencia es valida solo si la entrada ocurrio ANTES de
                    // concluir el trabajo y la salida fue posterior (o sigue abierta).
                    // Se limita a 16 horas para no arrastrar jornadas abiertas de dias previos.
                    $attendance = [];
                    $earliest = Carbon::parse($first, 'UTC')->subHours(16)->format('Y-m-d H:i:s');
                    foreach (DB::table('washer_attendance_24n3')
                        ->where('company_id', $company)
                        ->whereIn('employee_id', array_keys($employeeIds))
                        ->where('check_in_at', '>=', $earliest)
                        ->where('check_in_at', '<', $end)
                        ->get(['employee_id','check_in_at','check_out_at']) as $mark) {
                        $attendance[(int)$mark->employee_id][] = $mark;
                    }
                    foreach ($lines as $line) {
                        $orderId = (int)$line->order_id;
                        $employee = $primaryByOrder[$orderId]
                            ?? ($line->commission_employee_id !== null
                                ? (int)$line->commission_employee_id : null);
                        $workDate = $orderDates[$orderId] ?? null;
                        if ($employee === null || $workDate === null
                            || !isset($names[$employee], $workTimes[$orderId])) continue;
                        $finishedAt = $workTimes[$orderId];
                        $hasValidAttendance = false;
                        foreach ($attendance[$employee] ?? [] as $mark) {
                            $checkIn = Carbon::parse($mark->check_in_at, 'UTC');
                            $checkOut = $mark->check_out_at === null
                                ? null : Carbon::parse($mark->check_out_at, 'UTC');
                            if ($checkIn->lte($finishedAt)
                                && $checkIn->diffInMinutes($finishedAt) <= 960
                                && ($checkOut === null || $checkOut->gte($finishedAt))) {
                                $hasValidAttendance = true;
                                break;
                            }
                        }
                        if (!$hasValidAttendance) continue;
                        $percentage = (float)$line->commission_percent;
                        $price = (float)$line->price;
                        if ($percentage < 0 || $percentage > 100 || $price < 0) continue;
                        $cents = self::cents($price * $percentage / 100);
                        $days[$workDate]['commissions'] += $cents / 100;
                        if ($workDate === $today) {
                            if (!isset($production[$employee])) {
                                $production[$employee] = [
                                    'id'=>$employee, 'name'=>(string)$names[$employee],
                                    'completed'=>0, 'services'=>0,
                                    'commission_cents'=>0, 'orders'=>[]
                                ];
                            }
                            $production[$employee]['services']++;
                            $production[$employee]['commission_cents'] += $cents;
                            $production[$employee]['orders'][$orderId] = true;
                        }
                    }
                }
            }
        } else {
            $issues[] = 'Faltan tablas o campos para verificar comisiones y asistencia.';
        }
        $production = array_values(array_map(static function ($row): array {
            $row['completed'] = count($row['orders']);
            $row['commission'] = self::money($row['commission_cents']);
            unset($row['orders'], $row['commission_cents']);
            return $row;
        }, $production));
        usort($production, static fn($a,$b) => (float)$b['commission'] <=> (float)$a['commission']);
        $now = $days[$today] ?? ['services'=>null,'expenses'=>null,'commissions'=>null];
        $balance = $now['services'] !== null && $now['commissions'] !== null && $now['expenses'] !== null
            ? self::money(self::cents($now['services']) - self::cents($now['commissions']) - self::cents($now['expenses']))
            : null;
        return [
            'services_today'=>$now['services'] !== null ? self::money(self::cents($now['services'])) : null,
            'commissions_today'=>$now['commissions'] !== null ? self::money(self::cents($now['commissions'])) : null,
            'expenses_today'=>$now['expenses'] !== null ? self::money(self::cents($now['expenses'])) : null,
            'balance_today'=>$balance,
            'trend'=>array_values($days),
            'production'=>$production,
            'warnings'=>$issues,
        ];
    }
}
