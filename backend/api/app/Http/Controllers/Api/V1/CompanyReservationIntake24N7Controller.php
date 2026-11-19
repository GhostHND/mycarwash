<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Str;

/** 24N.7: reservas visibles sin confundir confirmación con recepción. */
class CompanyReservationIntake24N7Controller extends Controller
{
    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = (int) $request->user()->id;
        if (!DB::table('company_user as cu')->join('companies as c', 'c.id', '=', 'cu.company_id')
            ->where('cu.company_id', $company)->where('cu.user_id', $userId)
            ->where('cu.status', 'active')->where('c.is_active', true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($j): void {
            $j->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente.');
    }

    private function branch(int $company, int $id): object
    {
        return DB::table('branches')->where('company_id', $company)->where('id', $id)
            ->where('is_active', true)->first() ?? abort(404, 'Sucursal no disponible.');
    }

    private function source(int $company)
    {
        return DB::table('wash_bookings as b')
            ->join('branches as branch', function ($j): void {
                $j->on('branch.id', '=', 'b.branch_id')->on('branch.company_id', '=', 'b.company_id');
            })->join('vehicles as v', function ($j): void {
                $j->on('v.id', '=', 'b.vehicle_id')->on('v.company_id', '=', 'b.company_id');
            })->leftJoin('clients as c', function ($j): void {
                $j->on('c.id', '=', 'v.client_id')->on('c.company_id', '=', 'v.company_id');
            })->join('wash_services as s', function ($j): void {
                $j->on('s.id', '=', 'b.service_id')->on('s.company_id', '=', 'b.company_id');
            })->leftJoin('wash_bays as bay', function ($j): void {
                $j->on('bay.id', '=', 'b.bay_id')->on('bay.company_id', '=', 'b.company_id');
            })->leftJoin('booking_daily_assignments as a', function ($j): void {
                $j->on('a.booking_id', '=', 'b.id')->on('a.company_id', '=', 'b.company_id')
                    ->on('a.booking_start_utc', '=', 'b.start_at_utc');
            })->leftJoin('employees as e', function ($j): void {
                $j->on('e.id', '=', 'a.employee_id')->on('e.company_id', '=', 'b.company_id');
            })->leftJoin('booking_order_links_24n7 as link', function ($j): void {
                $j->on('link.booking_id', '=', 'b.id')->on('link.company_id', '=', 'b.company_id');
            })->where('b.company_id', $company)->whereNull('b.deleted_at')
            ->where('b.status', 'CONFIRMED');
    }

    private function fields(): array
    {
        return ['b.id', 'b.booking_code', 'b.local_date', 'b.start_at_utc', 'b.end_at_utc',
            'b.estimated_minutes', 'b.quoted_price', 'b.vehicle_id', 'b.service_id', 'b.bay_id',
            'b.branch_id', 'branch.name as branch_name', 'branch.timezone', 'v.brand', 'v.model',
            'v.plate', 'c.full_name as client_name', 's.name as service_name', 'bay.name as bay_name',
            'a.employee_id as proposed_employee_id', 'e.full_name as proposed_employee_name',
            'link.order_id', 'link.received_at'];
    }

    private function present(object $row): array
    {
        $entry = (array) $row;
        $zone = $row->timezone ?: 'America/Tegucigalpa';
        $entry['local_time'] = CarbonImmutable::parse($row->start_at_utc, 'UTC')
            ->setTimezone($zone)->format('H:i');
        $entry['vehicle_label'] = trim(($row->brand ?? '').' '.($row->model ?? ''));
        $entry['received'] = $row->order_id !== null;
        return $entry;
    }

    public function index(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $input = $request->validate(['date' => ['required', 'date_format:Y-m-d'],
            'branch_id' => ['sometimes', 'integer', 'min:1'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'between:1,100'],
            'q' => ['sometimes', 'nullable', 'string', 'max:120']]);
        if (isset($input['branch_id'])) $this->branch($company, (int) $input['branch_id']);
        $query = $this->source($company)->where('b.local_date', $input['date']);
        $search = trim((string) ($input['q'] ?? ''));
        if ($search !== '') {
            $query->where(function ($q) use ($search): void {
                $q->where('b.booking_code', 'like', '%'.$search.'%')
                    ->orWhere('v.plate', 'like', '%'.$search.'%')
                    ->orWhere('v.brand', 'like', '%'.$search.'%')
                    ->orWhere('v.model', 'like', '%'.$search.'%')
                    ->orWhere('c.full_name', 'like', '%'.$search.'%');
            });
        }
        if (isset($input['branch_id'])) $query->where('b.branch_id', $input['branch_id']);
        $totalPending = (clone $query)->whereNull('link.order_id')->count();
        $page = $query->select($this->fields())->orderBy('b.start_at_utc')->orderBy('b.id')
            ->paginate($input['per_page'] ?? 20)->toArray();
        $page['data'] = array_map(fn ($r) => $this->present((object) $r), $page['data']);
        $page['pending_reception'] = $totalPending;
        return response()->json($page);
    }

    /** Avisos visibles en el administrador abierto, 10 min antes del horario. */
    public function reminders(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $input = $request->validate(['branch_id' => ['sometimes', 'integer', 'min:1']]);
        if (isset($input['branch_id'])) $this->branch($company, (int) $input['branch_id']);
        $now = CarbonImmutable::now('UTC');
        $query = $this->source($company)->whereNull('link.order_id')
            ->where('b.start_at_utc', '>=', $now->format('Y-m-d H:i:s'))
            ->where('b.start_at_utc', '<=', $now->addMinutes(10)->format('Y-m-d H:i:s'))
            ->whereNotExists(function ($q) use ($company, $request): void {
                $q->select(DB::raw('1'))->from('booking_arrival_alert_reads_24n7 as seen')
                    ->whereColumn('seen.booking_id', 'b.id')
                    ->whereColumn('seen.booking_start_utc', 'b.start_at_utc')
                    ->where('seen.company_id', $company)
                    ->where('seen.user_id', (int) $request->user()->id);
            });
        if (isset($input['branch_id'])) $query->where('b.branch_id', $input['branch_id']);
        $list = $query->select($this->fields())->orderBy('b.start_at_utc')->limit(30)->get()
            ->map(fn ($r) => $this->present($r));
        return response()->json(['data' => $list]);
    }

    public function acknowledge(Request $request, int $company, int $booking): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $row = DB::table('wash_bookings')->where('company_id', $company)->where('id', $booking)
            ->whereNull('deleted_at')->first() ?? abort(404);
        DB::table('booking_arrival_alert_reads_24n7')->updateOrInsert(
            ['company_id' => $company, 'booking_id' => $booking,
                'user_id' => (int) $request->user()->id, 'booking_start_utc' => $row->start_at_utc],
            ['created_at' => now(), 'updated_at' => now()]
        );
        return response()->json(['message' => 'Aviso registrado.']);
    }

    /** Recepción idempotente: una reserva = una orden; asignación operativa posterior. */
    public function receive(Request $request, int $company, int $booking): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $result = DB::transaction(function () use ($company, $booking, $request): array {
            $b = DB::table('wash_bookings')->where('company_id', $company)->where('id', $booking)
                ->whereNull('deleted_at')->lockForUpdate()->first();
            if (!$b || $b->status !== 'CONFIRMED') {
                throw ValidationException::withMessages(['booking' => 'La reserva no está confirmada.']);
            }
            $existing = DB::table('booking_order_links_24n7')->where('company_id', $company)
                ->where('booking_id', $booking)->first();
            if ($existing) {
                return ['booking_id' => $booking, 'order_id' => (int) $existing->order_id, 'already_received' => true];
            }
            $branch = $this->branch($company, (int) $b->branch_id);
            $today = CarbonImmutable::now($branch->timezone)->toDateString();
            if ($b->local_date !== $today) {
                throw ValidationException::withMessages(['booking' => 'La recepción debe registrarse el día de la cita.']);
            }
            DB::table('vehicles')->where('company_id', $company)->where('id', $b->vehicle_id)->lockForUpdate()->first();
            if (DB::table('wash_orders')->where('company_id', $company)->where('vehicle_id', $b->vehicle_id)
                ->whereIn('status', ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO', 'TERMINADO'])->exists()) {
                throw ValidationException::withMessages(['vehicle_id' => 'El vehículo ya tiene una orden pendiente de entrega.']);
            }
            $now = now();
            $orderId = DB::table('wash_orders')->insertGetId([
                'public_id' => (string) Str::uuid(), 'tracking_code' => 'MCW-'.strtoupper(bin2hex(random_bytes(10))),
                'company_id' => $company, 'branch_id' => $b->branch_id, 'vehicle_id' => $b->vehicle_id,
                'service_id' => $b->service_id, 'bay_id' => $b->bay_id,
                'status' => 'EN_ESPERA', 'quoted_price' => $b->quoted_price,
                'estimated_minutes' => $b->estimated_minutes, 'notes' => $b->notes,
                'version' => 1, 'created_at' => $now, 'updated_at' => $now,
            ]);
            DB::table('booking_order_links_24n7')->insert([
                'company_id' => $company, 'booking_id' => $booking, 'order_id' => $orderId,
                'received_by_user_id' => (int) $request->user()->id,
                'received_at' => $now, 'created_at' => $now, 'updated_at' => $now,
            ]);
            DB::table('wash_order_events')->insert([
                'company_id' => $company, 'order_id' => $orderId,
                'from_status' => null, 'to_status' => 'EN_ESPERA',
                'reason' => 'Vehículo recibido · reserva '.$b->booking_code,
                'actor_user_id' => (int) $request->user()->id, 'occurred_at' => $now,
            ]);
            DB::table('booking_events')->insert([
                'company_id' => $company, 'booking_id' => $booking,
                'action' => 'RECEIVED', 'from_status' => 'CONFIRMED', 'to_status' => 'CONFIRMED',
                'actor_user_id' => (int) $request->user()->id, 'occurred_at' => $now,
            ]);
            return ['booking_id' => $booking, 'order_id' => $orderId, 'already_received' => false];
        }, 3);
        return response()->json(['message' => $result['already_received'] ? 'Vehículo recibido anteriormente.'
            : 'Vehículo recibido. Orden creada en Nuevas, pendiente de asignación.', 'data' => $result]);
    }
}
