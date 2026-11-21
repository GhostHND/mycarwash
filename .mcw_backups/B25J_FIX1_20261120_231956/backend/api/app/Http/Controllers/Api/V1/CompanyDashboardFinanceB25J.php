<?php

namespace App\Http\Controllers\Api\V1;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** B25J: servicios cobrados, comisiones con asistencia y egresos de caja.
 * Solo consultas. No altera ni liquida comisiones. Excluye POS de artículos.
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
        $hasPos = self::has('pos_sales', ['company_id', 'branch_id', 'wash_order_id', 'wash_price_snapshot', 'status', 'posted_at']);
        $hasOrders = self::has('wash_orders', ['id', 'company_id', 'branch_id', 'status', 'completed_at', 'deleted_at']);
        if ($hasOrders && ($hasPayments || $hasPos)) {
            foreach ($days as &$entry) $entry['services'] = 0.0;
            unset($entry);
            if ($hasPayments) {
                $query = DB::table('wash_order_payments as p')
                    ->join('wash_orders as o', function ($join): void {
                        $join->on('o.id', '=', 'p.order_id')->on('o.company_id', '=', 'p.company_id');
                    })
                    ->where('p.company_id', $company)->where('p.status', 'POSTED')
                    ->whereNull('p.deleted_at')->whereNull('o.deleted_at')
                    ->where('p.posted_at', '>=', $first)->where('p.posted_at', '<', $end);
                if ($branch !== null) $query->where('o.branch_id', $branch);
                foreach ($query->get(['p.order_id', 'p.posted_at', 'p.amount']) as $item) {
                    $day = Carbon::parse($item->posted_at, 'UTC')->setTimezone($timezone)->toDateString();
                    if (!isset($days[$day])) continue;
                    $days[$day]['services'] += (float) $item->amount;
                    $paid[(int) $item->order_id][$day] = true;
                }
            }
            if ($hasPos) {
                // Cobros POS vinculados a un lavado: el importe de artículos NO cuenta como servicios.
                $query = DB::table('pos_sales as s')
                    ->join('wash_orders as o', function ($join): void {
                        $join->on('o.id', '=', 's.wash_order_id')->on('o.company_id', '=', 's.company_id');
                    })
                    ->where('s.company_id', $company)->where('s.status', 'POSTED')
                    ->whereNotNull('s.wash_order_id')->whereNotNull('s.wash_price_snapshot')
                    ->where('s.posted_at', '>=', $first)->where('s.posted_at', '<', $end)
                    ->whereNull('o.deleted_at');
                if ($branch !== null) $query->where('s.branch_id', $branch);
                $linked = $query->get(['s.wash_order_id', 's.posted_at', 's.wash_price_snapshot']);
                $ids = $linked->pluck('wash_order_id')->unique()->values()->all();
                $paidElsewhere = $hasPayments && $ids
                    ? DB::table('wash_order_payments')->where('company_id', $company)
                        ->whereIn('order_id', $ids)->where('status', 'POSTED')
                        ->whereNull('deleted_at')->pluck('order_id')->map(fn($id) => (int)$id)->all()
                    : [];
                foreach ($linked as $item) {
                    $order = (int) $item->wash_order_id;
                    if (in_array($order, $paidElsewhere, true)) continue; // Evita cobro duplicado.
                    $day = Carbon::parse($item->posted_at, 'UTC')->setTimezone($timezone)->toDateString();
                    if (!isset($days[$day])) continue;
                    $days[$day]['services'] += (float) $item->wash_price_snapshot;
                    $paid[$order][$day] = true;
                }
            }
        } else {
            $issues[] = 'No se pudo verificar la fuente de cobros de servicios.';
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

        $production = [];
        $commissionsAvailable = self::has('wash_order_service_lines_b25',
                ['company_id','order_id','commission_employee_id','commission_amount'])
            && self::has('washer_attendance_24n3', ['company_id','employee_id','work_date','check_in_at'])
            && self::has('employees', ['id','company_id','full_name']);
        if ($commissionsAvailable && $hasOrders && ($hasPayments || $hasPos)) {
            foreach ($days as &$entry) $entry['commissions'] = 0.0;
            unset($entry);
            if ($paid) {
                $orders = DB::table('wash_orders')->where('company_id', $company)
                    ->whereIn('id', array_keys($paid))->whereNull('deleted_at')
                    ->whereIn('status', ['TERMINADO', 'ENTREGADO'])->get(['id','completed_at']);
                $orderDates = [];
                foreach ($orders as $order) {
                    if ($order->completed_at) {
                        $orderDates[(int) $order->id] = Carbon::parse($order->completed_at, 'UTC')
                            ->setTimezone($timezone)->toDateString();
                    }
                }
                if ($orderDates) {
                    $lines = DB::table('wash_order_service_lines_b25 as l')
                        ->join('employees as e', function ($join): void {
                            $join->on('e.id','=','l.commission_employee_id')
                                ->on('e.company_id','=','l.company_id');
                        })->where('l.company_id',$company)->whereIn('l.order_id',array_keys($orderDates))
                        ->whereNotNull('l.commission_employee_id')
                        ->get(['l.order_id','l.commission_employee_id','l.commission_amount','e.full_name']);
                    $employees = $lines->pluck('commission_employee_id')->unique()->values()->all();
                    $attended = [];
                    if ($employees) {
                        foreach (DB::table('washer_attendance_24n3')->where('company_id',$company)
                            ->whereIn('employee_id',$employees)->whereIn('work_date',array_values(array_unique($orderDates)))
                            ->whereNotNull('check_in_at')->get(['employee_id','work_date']) as $mark) {
                            $attended[(int)$mark->employee_id][(string)$mark->work_date] = true;
                        }
                    }
                    // Una orden genera comisión una sola vez aunque tenga varios pagos.
                    foreach ($lines as $line) {
                        $order = (int)$line->order_id;
                        $employee = (int)$line->commission_employee_id;
                        $dateWorked = $orderDates[$order] ?? null;
                        if (!$dateWorked || empty($attended[$employee][$dateWorked])) continue;
                        $postedDays = array_keys($paid[$order] ?? []);
                        sort($postedDays);
                        $postedDay = end($postedDays); // Jornada del último cobro verificado del período.
                        if (!$postedDay || !isset($days[$postedDay])) continue;
                        $cents = self::cents($line->commission_amount);
                        $days[$postedDay]['commissions'] += $cents / 100;
                        if ($postedDay === $today) {
                            if (!isset($production[$employee])) {
                                $production[$employee] = ['id'=>$employee,'name'=>(string)$line->full_name,
                                    'completed'=>0,'services'=>0,'commission_cents'=>0,'orders'=>[]];
                            }
                            $production[$employee]['services']++;
                            $production[$employee]['commission_cents'] += $cents;
                            $production[$employee]['orders'][$order] = true;
                        }
                    }
                }
            }
        } else $issues[] = 'Falta una fuente verificable de comisión o asistencia.';
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
