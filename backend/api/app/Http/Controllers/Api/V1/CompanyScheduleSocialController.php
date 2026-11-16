<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CompanyScheduleSocialController extends Controller
{
    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = $request->user()->id;

        $member = DB::table('company_user')
            ->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)
            ->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)
            ->exists();

        abort_unless($member, 404, 'Empresa no disponible.');

        $allowed = DB::table('user_roles as ur')
            ->join('roles as r', function ($join) {
                $join->on('r.id', '=', 'ur.role_id')
                    ->on('r.company_id', '=', 'ur.company_id');
            })
            ->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)
            ->where('ur.user_id', $userId)
            ->where('p.code', $permission)
            ->exists();

        abort_unless($allowed, 403, 'No tienes permiso para esta operaciÃ³n.');
    }

    private function lockCompany(int $company): void
    {
        DB::table('companies')->where('id', $company)->lockForUpdate()->first(['id']);
    }

    // ConvenciÃ³n del horario semanal: domingo = 0, lunes = 1, ... sÃ¡bado = 6.
    // Horarios en hora local del negocio; no se aceptan turnos que crucen medianoche.
    public function weekly(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');

        return response()->json([
            'day_convention' => '0=domingo,1=lunes,2=martes,3=miercoles,4=jueves,5=viernes,6=sabado',
            'days' => DB::table('company_business_hours')
                ->where('company_id', $company)
                ->orderBy('day_of_week')
                ->get(),
        ]);
    }

    public function saveWeekly(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.hours.manage');

        $data = $request->validate([
            'days' => ['required', 'array', 'min:1', 'max:7'],
            'days.*.day_of_week' => ['required', 'integer', 'between:0,6', 'distinct'],
            'days.*.is_closed' => ['required', 'boolean'],
            'days.*.opens_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'days.*.closes_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'days.*.break_starts_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'days.*.break_ends_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'days.*.notes' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $normalized = [];
        foreach ($data['days'] as $index => $day) {
            $closed = (bool) $day['is_closed'];
            $open = $day['opens_at'] ?? null;
            $close = $day['closes_at'] ?? null;
            $breakStart = $day['break_starts_at'] ?? null;
            $breakEnd = $day['break_ends_at'] ?? null;

            if (!$closed) {
                if (!$open || !$close || $open >= $close) {
                    throw ValidationException::withMessages([
                        "days.$index.opens_at" => 'La apertura debe ser anterior al cierre y ambos horarios son obligatorios.',
                    ]);
                }
                if (($breakStart === null) !== ($breakEnd === null)) {
                    throw ValidationException::withMessages([
                        "days.$index.break_starts_at" => 'El descanso requiere inicio y fin.',
                    ]);
                }
                if ($breakStart !== null && !($open <= $breakStart && $breakStart < $breakEnd && $breakEnd <= $close)) {
                    throw ValidationException::withMessages([
                        "days.$index.break_starts_at" => 'El descanso debe estar dentro de la jornada.',
                    ]);
                }
            } else {
                $open = $close = $breakStart = $breakEnd = null;
            }

            $normalized[] = [
                'day_of_week' => (int) $day['day_of_week'],
                'is_closed' => $closed,
                'opens_at' => $open,
                'closes_at' => $close,
                'break_starts_at' => $breakStart,
                'break_ends_at' => $breakEnd,
                'notes' => $day['notes'] ?? null,
            ];
        }

        DB::transaction(function () use ($company, $normalized) {
            $this->lockCompany($company);

            foreach ($normalized as $day) {
                $weekday = $day['day_of_week'];
                unset($day['day_of_week']);
                $query = DB::table('company_business_hours')
                    ->where('company_id', $company)
                    ->where('day_of_week', $weekday);

                if ((clone $query)->exists()) {
                    $query->update(array_merge($day, ['updated_at' => now()]));
                } else {
                    DB::table('company_business_hours')->insert(array_merge($day, [
                        'company_id' => $company,
                        'day_of_week' => $weekday,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]));
                }
            }
        });

        return response()->json([
            'message' => 'Horarios semanales guardados.',
            'day_convention' => '0=domingo,1=lunes,2=martes,3=miercoles,4=jueves,5=viernes,6=sabado',
            'days' => DB::table('company_business_hours')->where('company_id', $company)
                ->orderBy('day_of_week')->get(),
        ]);
    }

    private function specialRules(bool $create): array
    {
        return [
            'special_date' => [$create ? 'required' : 'sometimes', 'date_format:Y-m-d'],
            'reason' => ['sometimes', 'nullable', 'string', 'max:190'],
            'is_closed' => ['sometimes', 'boolean'],
            'opens_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'closes_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
        ];
    }

    private function normalizeSpecial(array $data, ?object $current = null): array
    {
        $closed = (bool) ($data['is_closed'] ?? $current?->is_closed ?? false);
        $open = array_key_exists('opens_at', $data)
            ? $data['opens_at']
            : ($current?->opens_at ? substr((string) $current->opens_at, 0, 5) : null);
        $close = array_key_exists('closes_at', $data)
            ? $data['closes_at']
            : ($current?->closes_at ? substr((string) $current->closes_at, 0, 5) : null);

        if ($closed) {
            $data['opens_at'] = null;
            $data['closes_at'] = null;
        } else {
            if (!$open || !$close || $open >= $close) {
                throw ValidationException::withMessages([
                    'opens_at' => 'Indica apertura y cierre vÃ¡lidos dentro del mismo dÃ­a.',
                ]);
            }
            $data['opens_at'] = $open;
            $data['closes_at'] = $close;
        }
        $data['is_closed'] = $closed;
        return $data;
    }

    public function special(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $filters = $request->validate([
            'from' => ['sometimes', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'date_format:Y-m-d'],
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'per_page' => ['sometimes', 'integer', 'between:1,50'],
        ]);

        $query = DB::table('company_special_hours')->where('company_id', $company);
        if (isset($filters['from'])) $query->where('special_date', '>=', $filters['from']);
        if (isset($filters['to'])) $query->where('special_date', '<=', $filters['to']);
        $q = trim((string) ($filters['q'] ?? ''));
        if ($q !== '') {
            $query->where(function ($builder) use ($q) {
                $builder->where('reason', 'like', "%$q%")
                    ->orWhere('notes', 'like', "%$q%")
                    ->orWhere('special_date', 'like', "%$q%");
            });
        }
        return response()->json($query->orderBy('special_date')->orderBy('id')
            ->paginate((int) ($filters['per_page'] ?? 20)));
    }

    public function storeSpecial(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.hours.manage');
        $data = $this->normalizeSpecial($request->validate($this->specialRules(true)));

        $id = DB::transaction(function () use ($company, $data) {
            $this->lockCompany($company);
            if (DB::table('company_special_hours')->where('company_id', $company)
                ->where('special_date', $data['special_date'])->exists()) {
                throw ValidationException::withMessages([
                    'special_date' => 'Ya existe un horario especial para esa fecha.',
                ]);
            }
            return DB::table('company_special_hours')->insertGetId(array_merge($data, [
                'company_id' => $company,
                'created_at' => now(),
                'updated_at' => now(),
            ]));
        });

        return response()->json([
            'message' => 'Horario especial creado.',
            'special' => DB::table('company_special_hours')->where('company_id', $company)->where('id', $id)->first(),
        ], 201);
    }

    public function updateSpecial(Request $request, int $company, int $special): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.hours.manage');
        $incoming = $request->validate($this->specialRules(false));
        if (!$incoming) return response()->json(['message' => 'No se recibieron cambios.'], 422);

        DB::transaction(function () use ($company, $special, $incoming) {
            $this->lockCompany($company);
            $current = DB::table('company_special_hours')->where('company_id', $company)
                ->where('id', $special)->first();
            abort_unless($current, 404, 'Horario especial no encontrado.');
            $data = $this->normalizeSpecial($incoming, $current);

            if (isset($data['special_date']) && $data['special_date'] !== $current->special_date &&
                DB::table('company_special_hours')->where('company_id', $company)
                    ->where('special_date', $data['special_date'])->where('id', '!=', $special)->exists()) {
                throw ValidationException::withMessages([
                    'special_date' => 'Ya existe un horario especial para esa fecha.',
                ]);
            }
            DB::table('company_special_hours')->where('company_id', $company)
                ->where('id', $special)->update(array_merge($data, ['updated_at' => now()]));
        });

        return response()->json([
            'message' => 'Horario especial actualizado.',
            'special' => DB::table('company_special_hours')->where('company_id', $company)->where('id', $special)->first(),
        ]);
    }

    public function deleteSpecial(Request $request, int $company, int $special): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.hours.manage');
        $deleted = DB::table('company_special_hours')->where('company_id', $company)->where('id', $special)->delete();
        abort_unless($deleted, 404, 'Horario especial no encontrado.');
        return response()->json(['message' => 'Horario especial eliminado.']);
    }

    private function socialRules(bool $create): array
    {
        return [
            'platform' => [$create ? 'required' : 'sometimes', 'string', 'regex:/^[a-z][a-z0-9_-]{0,59}$/'],
            'username' => ['sometimes', 'nullable', 'string', 'max:150'],
            'url' => [$create ? 'required' : 'sometimes', 'url:http,https', 'max:600'],
            'is_visible' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'between:0,100000'],
        ];
    }

    public function socials(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $filters = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'per_page' => ['sometimes', 'integer', 'between:1,50'],
        ]);
        $query = DB::table('company_social_links')->where('company_id', $company);
        $q = trim((string) ($filters['q'] ?? ''));
        if ($q !== '') {
            $query->where(function ($builder) use ($q) {
                $builder->where('platform', 'like', "%$q%")
                    ->orWhere('username', 'like', "%$q%")
                    ->orWhere('url', 'like', "%$q%");
            });
        }
        return response()->json($query->orderBy('sort_order')->orderBy('id')
            ->paginate((int) ($filters['per_page'] ?? 20)));
    }

    public function storeSocial(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $data = $request->validate($this->socialRules(true));
        $id = DB::table('company_social_links')->insertGetId(array_merge($data, [
            'company_id' => $company,
            'created_at' => now(),
            'updated_at' => now(),
        ]));
        return response()->json([
            'message' => 'Red social agregada.',
            'social' => DB::table('company_social_links')->where('company_id', $company)->where('id', $id)->first(),
        ], 201);
    }

    public function updateSocial(Request $request, int $company, int $social): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $data = $request->validate($this->socialRules(false));
        if (!$data) return response()->json(['message' => 'No se recibieron cambios.'], 422);
        $query = DB::table('company_social_links')->where('company_id', $company)
            ->where('id', $social);
        abort_unless((clone $query)->exists(), 404, 'Red social no encontrada.');
        $query->update(array_merge($data, ['updated_at' => now()]));
        return response()->json([
            'message' => 'Red social actualizada.',
            'social' => DB::table('company_social_links')->where('company_id', $company)->where('id', $social)->first(),
        ]);
    }

    public function deleteSocial(Request $request, int $company, int $social): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $deleted = DB::table('company_social_links')->where('company_id', $company)
            ->where('id', $social)->delete();
        abort_unless($deleted, 404, 'Red social no encontrada.');
        return response()->json(['message' => 'Red social eliminada.']);
    }
}