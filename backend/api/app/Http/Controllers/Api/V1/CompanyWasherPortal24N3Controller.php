<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\WasherAccess24N3;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Str;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Lavador: solamente sus órdenes, citas y perfil. El servidor impone el alcance. */
class CompanyWasherPortal24N3Controller extends Controller
{
    private function employee(Request $request, int $company): int
    {
        abort_unless(WasherAccess24N3::isWasher($company, (int) $request->user()->id), 403);
        return WasherAccess24N3::employeeId($company, (int) $request->user()->id);
    }

    public function branding(Request $request, int $company): JsonResponse
    {
        $this->employee($request, $company);
        return response()->json([
            'company' => DB::table('companies')->where('id', $company)->first(['id', 'name']),
            'profile' => DB::table('company_profiles')->where('company_id', $company)->first(['commercial_name']),
            'branding' => DB::table('company_brandings')->where('company_id', $company)->first(),
        ]);
    }

    public function orders(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request, $company);
        $filters = $request->validate([
            'page' => ['sometimes', 'integer', 'min:1'],
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'status' => ['sometimes', Rule::in(['TODAS','EN_ESPERA','ASIGNADO','EN_PROCESO','TERMINADO','ENTREGADO','CANCELADO'])],
        ]);
        $q = DB::table('wash_orders as o')->join('wash_assignments as a', function ($join): void {
            $join->on('a.order_id', '=', 'o.id')->on('a.company_id', '=', 'o.company_id');
        })->leftJoin('vehicles as v', function ($join): void {
            $join->on('v.id', '=', 'o.vehicle_id')->on('v.company_id', '=', 'o.company_id');
        })->leftJoin('wash_services as s', function ($join): void {
            $join->on('s.id', '=', 'o.service_id')->on('s.company_id', '=', 'o.company_id');
        })->where('o.company_id', $company)->where('a.employee_id', $employee)
          ->where('a.is_active', true);
        $hasClients = \Illuminate\Support\Facades\Schema::hasColumn('vehicles','client_id');
        if ($hasClients) {
            $q->leftJoin('clients as c', function ($join): void {
                $join->on('c.id','=','v.client_id')->on('c.company_id','=','o.company_id');
            });
        }
        if (trim((string) ($filters['q'] ?? '')) !== '') {
            $word = '%'.trim($filters['q']).'%';
            $q->where(function ($builder) use ($word, $hasClients): void {
                $builder->where('o.tracking_code', 'like', $word)
                  ->orWhere('v.plate', 'like', $word)
                  ->orWhere('v.brand', 'like', $word)
                  ->orWhere('v.model', 'like', $word);
                if ($hasClients) $builder->orWhere('c.full_name','like',$word);
            });
        }
        $counts = (clone $q)->select('o.status')->selectRaw('COUNT(DISTINCT o.id) as total')
            ->groupBy('o.status')->pluck('total', 'o.status');
        if (isset($filters['status']) && $filters['status'] !== 'TODAS') {
            $q->where('o.status', $filters['status']);
        }
        $page = $q->select('o.id','o.status','o.version','o.tracking_code','o.created_at',
            'o.started_at','o.completed_at','o.estimated_minutes', 'o.branch_id', 'o.vehicle_id',
            'v.brand','v.model','v.plate','s.name as service_name')
          ->distinct()->orderByDesc('o.id')->paginate(12);
        $result = $page->toArray();
        // Query Builder devuelve filas stdClass; paginate()->toArray() no convierte
        // las filas internas en arreglos asociativos.
        foreach ($result['data'] as $orderRow) {
            $orderRow->worker_finished = DB::table('wash_assignments')->where('company_id',$company)
                ->where('employee_id',$employee)->where('order_id',$orderRow->id)
                ->where('is_active',true)->whereNotNull('washer_finished_at')->exists();
        }
        $result['status_counts'] = $counts;
        // Datos completos únicamente para las órdenes ya autorizadas.
        $ids = array_map(static fn (object $row): int => (int) $row->id, $result['data']);
        if ($ids && \Illuminate\Support\Facades\Schema::hasColumn('wash_orders','quoted_price')
            && \Illuminate\Support\Facades\Schema::hasColumn('vehicles','client_id')) {
            $extras = DB::table('wash_orders as o')
                ->leftJoin('wash_bays as bay', function ($join): void {
                    $join->on('bay.id','=','o.bay_id')->on('bay.company_id','=','o.company_id');
                })->leftJoin('vehicles as v', function ($join): void {
                    $join->on('v.id','=','o.vehicle_id')->on('v.company_id','=','o.company_id');
                })->leftJoin('clients as c', function ($join): void {
                    $join->on('c.id','=','v.client_id')->on('c.company_id','=','o.company_id');
                })->where('o.company_id',$company)->whereIn('o.id',$ids)
                ->select('o.id','o.quoted_price','bay.name as bay_name','c.full_name as client_name')
                ->get()->keyBy('id');
            foreach ($result['data'] as $orderRow) {
                $extra = $extras->get($orderRow->id);
                $orderRow->quoted_price = $extra?->quoted_price;
                $orderRow->bay_name = $extra?->bay_name;
                $orderRow->client_name = $extra?->client_name;
            }
        }
        return response()->json($result);
    }

    /** Resumen personal: la fecha se mide en la zona de trabajo, no en la del navegador. */
    public function summary(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request,$company);
        $q = DB::table('wash_assignments as a')->join('wash_orders as o',function ($join): void {
            $join->on('o.id','=','a.order_id')->on('o.company_id','=','a.company_id');
        })->leftJoin('vehicles as v', function ($join): void {
            $join->on('v.id','=','o.vehicle_id')->on('v.company_id','=','o.company_id');
        })->leftJoin('wash_services as s', function ($join): void {
            $join->on('s.id','=','o.service_id')->on('s.company_id','=','o.company_id');
        })->where('a.company_id',$company)->where('a.employee_id',$employee)->where('a.is_active',true);
        $fields=['o.id','o.status','o.version','o.tracking_code','o.vehicle_id','o.started_at',
            'o.completed_at','o.estimated_minutes','v.brand','v.model','v.plate','s.name as service_name'];
        $active = (clone $q)->where('o.status','EN_PROCESO')->whereNull('a.washer_finished_at')
            ->select($fields)->orderBy('o.id')->first();
        $next = (clone $q)->whereIn('o.status',['EN_ESPERA','ASIGNADO'])
            ->select($fields)->orderBy('o.id')->first();
        $pending = (clone $q)->whereIn('o.status',['EN_ESPERA','ASIGNADO'])
            ->distinct()->count('o.id');
        $startLocal = CarbonImmutable::now('America/Tegucigalpa')->startOfDay()->utc()->format('Y-m-d H:i:s');
        $endLocal = CarbonImmutable::now('America/Tegucigalpa')->addDay()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $completed = (clone $q)->where(function ($builder) use ($startLocal, $endLocal): void {
            $builder->where(function ($sub) use ($startLocal,$endLocal): void {
                $sub->where('a.washer_finished_at','>=',$startLocal)->where('a.washer_finished_at','<',$endLocal);
            })->orWhere(function ($sub) use ($startLocal,$endLocal): void {
                $sub->whereNull('a.washer_finished_at')->whereIn('o.status',['TERMINADO','ENTREGADO'])
                    ->where('o.completed_at','>=',$startLocal)->where('o.completed_at','<',$endLocal);
            });
        })->distinct()->count('o.id');
        return response()->json(['active' => $active,'next' => $next,
            'completed_today' => $completed,'pending' => $pending,
            'in_queue' => $next ? 1 : 0]);
    }

    public function start(Request $request, int $company, int $order): JsonResponse
    {
        return $this->transition($request, $company, $order, 'start');
    }

    public function finish(Request $request, int $company, int $order): JsonResponse
    {
        return $this->transition($request, $company, $order, 'finish');
    }

    private function transition(Request $request, int $company, int $order, string $action): JsonResponse
    {
        $employee = $this->employee($request, $company);
        abort_unless(in_array($action, ['start','finish'], true), 404);
        abort_unless(WasherAccess24N3::assigned($company, $employee, $order), 403,
            'La orden no está asignada a tu usuario.');
        $data = $request->validate(['expected_version' => ['required','integer','min:1']]);
        $target = $action === 'start' ? 'EN_PROCESO' : 'TERMINADO';
        // Reutilizamos el motor existente: FIFO, bloqueo, concurrencia, eventos y activación de cola.
        // transition() verifica además la asignación dentro de su transacción.
        $request->merge(['to_status' => $target, 'expected_version' => $data['expected_version']]);
        return app(CompanyWashWorkflowController::class)->transition($request, $company, $order);
    }

    public function agenda(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request, $company);
        $input = $request->validate([
            'date' => ['required', 'date_format:Y-m-d'],
            'view' => ['required', Rule::in(['day','week','month'])],
        ]);
        // Se acota por fecha UTC ±1 día y se evalúa por zona de la sucursal.
        // No se consulta ninguna cita sin asignación a este empleado.
        $anchor = CarbonImmutable::parse($input['date'].' 00:00:00', 'UTC');
        $from = match ($input['view']) {
            'week' => $anchor->startOfWeek(), 'month' => $anchor->startOfMonth(), default => $anchor,
        };
        $until = match ($input['view']) {
            'week' => $from->addWeek(), 'month' => $from->addMonth(), default => $from->addDay(),
        };
        $items = DB::table('booking_daily_assignments as a')
            ->join('wash_bookings as b', function ($join): void {
                $join->on('b.id', '=', 'a.booking_id')->on('b.company_id', '=', 'a.company_id')
                    ->on('b.start_at_utc', '=', 'a.booking_start_utc');
            })->join('branches as branch', function ($join): void {
                $join->on('branch.id', '=', 'b.branch_id')->on('branch.company_id', '=', 'b.company_id');
            })->leftJoin('vehicles as v', function ($join): void {
                $join->on('v.id', '=', 'b.vehicle_id')->on('v.company_id', '=', 'b.company_id');
            })->leftJoin('wash_services as s', function ($join): void {
                $join->on('s.id', '=', 'b.service_id')->on('s.company_id', '=', 'b.company_id');
            })->where('a.company_id', $company)->where('a.employee_id', $employee)
              ->where('b.status', 'CONFIRMED')->whereNull('b.deleted_at')
              ->where('b.start_at_utc', '>=', $from->subDay()->format('Y-m-d H:i:s'))
              ->where('b.start_at_utc', '<', $until->addDay()->format('Y-m-d H:i:s'))
              ->select('b.id','b.booking_code','b.start_at_utc','b.end_at_utc','b.vehicle_id','b.status',
                'branch.name as branch_name','branch.timezone','v.brand','v.model','v.plate',
                's.name as service_name')->orderBy('b.start_at_utc')->limit(250)->get();
        $rows = $items->filter(function ($item) use ($from, $until): bool {
            $local = CarbonImmutable::parse($item->start_at_utc, 'UTC')->setTimezone($item->timezone ?: 'America/Tegucigalpa');
            $date = $local->toDateString();
            return $date >= $from->toDateString() && $date < $until->toDateString();
        })->map(function ($item): array {
            $local = CarbonImmutable::parse($item->start_at_utc, 'UTC')->setTimezone($item->timezone ?: 'America/Tegucigalpa');
            return ['id' => $item->id, 'booking_code' => $item->booking_code,
                'vehicle_id' => $item->vehicle_id, 'status' => $item->status,
                'date' => $local->toDateString(), 'time' => $local->format('H:i'),
                'branch' => $item->branch_name, 'vehicle' => trim($item->brand.' '.$item->model),
                'plate' => $item->plate, 'starts_at' => $item->start_at_utc,
                'service' => $item->service_name];
        })->values();
        return response()->json(['data' => $rows, 'view' => $input['view'], 'date' => $input['date']]);
    }

    public function me(Request $request, int $company): JsonResponse
    {
        $id = $this->employee($request, $company);
        $user = $request->user();
        $worker = DB::table('employees')->where('company_id', $company)->where('id', $id)
            ->first(['id','full_name','identity_document','hire_date','is_active','position','phone']);
        return response()->json(['user' => ['id' => $user->id, 'name' => $user->name,
            'email' => $user->email, 'employee_id' => $id,
            'phone' => $worker?->phone, 'full_name' => $worker?->full_name,
            'identity_document' => $worker?->identity_document, 'hire_date' => $worker?->hire_date,
            'role' => 'Lavador', 'is_active' => (bool) $worker?->is_active]]);
    }

    public function updateMe(Request $request, int $company): JsonResponse
    {
        $employeeId = $this->employee($request, $company);
        $user = $request->user();
        $data = $request->validate([
            'name' => ['required','string','min:2','max:180'],
            'email' => ['required','email','max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'phone' => ['sometimes','nullable','string','max:40'],
        ]);
        DB::table('users')->where('id', $user->id)->update([
            'name' => trim($data['name']), 'email' => mb_strtolower(trim($data['email'])),
            'updated_at' => now(),
        ]);
        if (array_key_exists('phone', $data)) {
            DB::table('employees')->where('company_id', $company)->where('id', $employeeId)
                ->update(['phone' => trim((string) ($data['phone'] ?? '')), 'updated_at' => now()]);
        }
        return response()->json(['message' => 'Datos personales actualizados.']);
    }

    public function password(Request $request, int $company): JsonResponse
    {
        $this->employee($request, $company);
        $input = $request->validate([
            'current_password' => ['required','string'],
            'password' => ['required','string','min:10','max:128','confirmed'],
        ]);
        $user = $request->user();
        if (!Hash::check($input['current_password'], $user->password)) {
            throw ValidationException::withMessages(['current_password' => 'La contraseña actual no es correcta.']);
        }
        DB::transaction(function () use ($user, $input): void {
            DB::table('users')->where('id', $user->id)->update([
                'password' => Hash::make($input['password']), 'updated_at' => now(),
            ]);
            DB::table('personal_access_tokens')->where('tokenable_type', User::class)
                ->where('tokenable_id', $user->id)->delete();
        });
        return response()->json(['message' => 'Contraseña actualizada. Debes iniciar sesión nuevamente.']);
    }

    /** Registro personal; un lavador no puede registrar asistencia de otro. */
    public function attendance(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request, $company);
        $data = $request->validate([
            'month' => ['sometimes','date_format:Y-m'],
        ]);
        $month = $data['month'] ?? now('America/Tegucigalpa')->format('Y-m');
        $from = CarbonImmutable::createFromFormat('!Y-m-d', $month.'-01', 'America/Tegucigalpa')->startOfDay();
        $until = $from->addMonth();
        $history = DB::table('washer_attendance_24n3')
            ->where('company_id', $company)->where('employee_id', $employee)
            ->where('work_date','>=',$from->toDateString())
            ->where('work_date','<',$until->toDateString())
            ->orderByDesc('check_in_at')->limit(40)->get(['id','work_date','check_in_at','check_out_at']);
        $open = DB::table('washer_attendance_24n3')
            ->where('company_id', $company)->where('employee_id', $employee)
            ->whereNull('check_out_at')->orderByDesc('check_in_at')
            ->first(['id','work_date','check_in_at']);
        return response()->json(['month' => $month, 'data' => $history,
            'on_duty' => $open !== null, 'active' => $open,
            'timezone' => 'America/Tegucigalpa']);
    }

    public function checkIn(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request, $company);
        return DB::transaction(function () use ($company, $employee, $request): JsonResponse {
            DB::table('employees')->where('company_id',$company)->where('id',$employee)->lockForUpdate()->first();
            abort_if(DB::table('washer_attendance_24n3')->where('company_id',$company)
                ->where('employee_id',$employee)->whereNull('check_out_at')->exists(), 409,
                'Ya registraste una entrada. Primero marca tu salida.');
            $today = now('America/Tegucigalpa')->toDateString();
            abort_if(DB::table('washer_attendance_24n3')->where('company_id',$company)
                ->where('employee_id',$employee)->where('work_date',$today)->exists(), 409,
                'Tu asistencia de hoy ya fue registrada.');
            DB::table('washer_attendance_24n3')->insert([
                'company_id' => $company, 'employee_id' => $employee,
                'work_date' => $today, 'check_in_at' => now('UTC'),
                'check_out_at' => null, 'created_at' => now(), 'updated_at' => now(),
            ]);
            return response()->json(['message' => 'Entrada registrada correctamente.'], 201);
        });
    }

    public function checkOut(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request, $company);
        return DB::transaction(function () use ($company, $employee): JsonResponse {
            DB::table('employees')->where('company_id',$company)->where('id',$employee)->lockForUpdate()->first();
            $open = DB::table('washer_attendance_24n3')->where('company_id',$company)
                ->where('employee_id',$employee)->whereNull('check_out_at')
                ->orderByDesc('check_in_at')->lockForUpdate()->first();
            abort_if(!$open, 409, 'No tienes una entrada pendiente de salida.');
            DB::table('washer_attendance_24n3')->where('id',$open->id)
                ->whereNull('check_out_at')->update(['check_out_at' => now('UTC'), 'updated_at' => now()]);
            return response()->json(['message' => 'Salida registrada correctamente.']);
        });
    }


    /** Foto privada: solo su retrato o un vehículo vinculado a sus órdenes/reservas. */
    public function photo(Request $request, int $company, string $kind, int $record): Response
    {
        $employee = $this->employee($request, $company);
        abort_unless(in_array($kind, ['vehicles','employees'], true), 404);
        if ($kind === 'employees') {
            abort_unless($employee === $record, 403);
        } else {
            $inOrders = DB::table('wash_assignments as a')->join('wash_orders as o', function ($join): void {
                $join->on('o.id','=','a.order_id')->on('o.company_id','=','a.company_id');
            })->where('a.company_id',$company)->where('a.employee_id',$employee)
                ->where('a.is_active',true)->where('o.vehicle_id',$record)->exists();
            $inBookings = DB::table('booking_daily_assignments as a')->join('wash_bookings as b', function ($join): void {
                $join->on('b.id','=','a.booking_id')->on('b.company_id','=','a.company_id');
            })->where('a.company_id',$company)->where('a.employee_id',$employee)
                ->whereNull('b.deleted_at')->where('b.vehicle_id',$record)->exists();
            abort_unless($inOrders || $inBookings, 403);
        }
        $media = DB::table('company_entity_photos as p')->join('company_media_assets as m', function ($join): void {
            $join->on('m.id','=','p.media_asset_id')->on('m.company_id','=','p.company_id');
        })->where('p.company_id',$company)->where('p.owner_type',$kind)->where('p.owner_id',$record)
            ->first(['m.disk','m.path','m.mime_type']);
        abort_unless($media && $media->disk === 'local' && Storage::disk('local')->exists($media->path), 404);
        return response(Storage::disk('local')->get($media->path), 200, [
            'Content-Type' => $media->mime_type ?? 'image/jpeg',
            'Cache-Control' => 'private, no-store',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    /** Código dinámico de punto autorizado. El QR NO indica por sí solo una entrada. */
    public function scanAttendance(Request $request, int $company): JsonResponse
    {
        $employee = $this->employee($request, $company);
        abort_unless(\Illuminate\Support\Facades\RateLimiter::attempt('attendance:'.$company.':'.$employee,10,fn () => true,60), 429, 'Demasiados intentos.');
        $input = $request->validate([
            'code' => ['required','string','max:512'],
            'event' => ['required', Rule::in(['check_in','check_out'])],
        ]);
        $code = trim($input['code']);
        $point = null;
        $usedSlot = null;
        // QR permanente firmado por punto. No autentica por sí solo al empleado.
        if (preg_match('/^MCW:ATT:2:(\d+):(\d+):([a-f0-9]{40})$/i', $code, $matches)) {
            abort_unless((int) $matches[1] === $company, 422, 'QR de otra empresa.');
            $point = DB::table('washer_attendance_points_24n4')->where('company_id',$company)
                ->where('id',(int)$matches[2])->where('is_active',true)->first();
            abort_unless($point, 422, 'Punto de asistencia no autorizado.');
            $expected = hash_hmac('sha256', "MCW:ATT:2:$company:{$point->id}", Crypt::decryptString($point->secret_encrypted));
            abort_unless(hash_equals(substr($expected,0,40),strtolower($matches[3])), 422, 'Código QR no válido.');
            $usedSlot = 0; // identificador estable; limitadores por empleado y jornada siguen activos.
        } elseif (preg_match('/^MCW:ATT:1:(\d+):(\d+):(\d+):([a-f0-9]{40})$/i', $code, $matches)) {
            // Compatibilidad con QR temporal anterior.


            abort_unless((int) $matches[1] === $company, 422, 'QR de otra empresa.');
            $point = DB::table('washer_attendance_points_24n4')->where('company_id',$company)
                ->where('id',(int)$matches[2])->where('is_active',true)->first();
            abort_unless($point, 422, 'Punto de asistencia no autorizado.');
            $usedSlot = (int) $matches[3];
            abort_unless(abs(intdiv(time(),120) - $usedSlot) <= 1, 422, 'Código caducado. Escanea uno nuevo.');
            $signature = hash_hmac('sha256', "$company:{$point->id}:$usedSlot", Crypt::decryptString($point->secret_encrypted));
            abort_unless(hash_equals(substr($signature,0,40),strtolower($matches[4])), 422, 'Código QR no válido.');
        } elseif (preg_match('/^\d{8}$/', $code)) {
            $points = DB::table('washer_attendance_points_24n4')->where('company_id',$company)
                ->where('is_active',true)->get();
            foreach ($points as $candidate) {
                foreach (range(intdiv(time(),120)-1,intdiv(time(),120)+1) as $slot) {
                    $signature = hash_hmac('sha256', "$company:{$candidate->id}:$slot", Crypt::decryptString($candidate->secret_encrypted));
                    $digits = substr(str_pad((string)(hexdec(substr($signature,0,8)) % 100000000),8,'0',STR_PAD_LEFT),0,8);
                    if (hash_equals($digits,$code)) { $point = $candidate; $usedSlot = $slot; break 2; }
                }
            }
            abort_unless($point, 422, 'Código manual inválido o vencido.');
        } else {
            abort(422, 'Código de asistencia no reconocido.');
        }
        // Una misma captura no se puede repetir; la restricción no reemplaza las reglas de jornada.
        $fingerprint = hash('sha256', "$company:$employee:{$point->id}:$usedSlot:{$input['event']}");
        abort_unless(Cache::add('washer-attendance:'.$fingerprint, 1, now()->addMinutes(4)), 409,
            'Este código ya fue utilizado para ese movimiento.');
        try {
            return $input['event'] === 'check_in' ? $this->checkIn($request,$company) : $this->checkOut($request,$company);
        } catch (\Throwable $error) {
            Cache::forget('washer-attendance:'.$fingerprint);
            throw $error;
        }
    }

}
