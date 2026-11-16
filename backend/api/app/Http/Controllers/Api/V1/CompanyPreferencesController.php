<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class CompanyPreferencesController extends Controller
{
    private const FIELDS = [
        'locale', 'currency_code', 'timezone', 'date_format', 'time_format',
        'default_theme', 'invoice_paper_size', 'country_phone_code',
        'decimal_places', 'enable_sound_alerts', 'receipt_footer',
    ];

    private const DEFAULTS = [
        'locale' => 'es-HN',
        'currency_code' => 'HNL',
        'timezone' => 'America/Tegucigalpa',
        'date_format' => 'dd/MM/yyyy',
        'time_format' => '24h',
        'default_theme' => 'system',
        'invoice_paper_size' => 'letter',
        'country_phone_code' => '+504',
        'decimal_places' => 2,
        'enable_sound_alerts' => true,
        'receipt_footer' => null,
    ];

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

        abort_unless($allowed, 403, 'No tienes permiso para esta operacion.');
    }

    private function normalizedPreferences(int $company): array
    {
        $row = DB::table('company_preferences')
            ->where('company_id', $company)->first(self::FIELDS);
        $preferences = self::DEFAULTS;
        if ($row !== null) {
            foreach (self::FIELDS as $field) {
                $preferences[$field] = $row->{$field};
            }
            $preferences['decimal_places'] = (int) $preferences['decimal_places'];
            $preferences['enable_sound_alerts'] = (bool) $preferences['enable_sound_alerts'];
        }
        return $preferences;
    }

    public function show(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        return response()->json(['preferences' => $this->normalizedPreferences($company)]);
    }

    public function update(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');

        // No aceptar company_id, campos de auditoria ni datos del Software Master.
        $unknown = array_diff(array_keys($request->all()), self::FIELDS);
        if ($unknown !== []) {
            return response()->json([
                'message' => 'La solicitud contiene campos no permitidos.',
            ], 422);
        }

        $data = $request->validate([
            'locale' => ['sometimes', 'string', 'max:12', 'regex:/^[a-z]{2}(?:-[A-Z]{2})?$/'],
            'currency_code' => ['sometimes', 'string', 'size:3', 'regex:/^[A-Z]{3}$/'],
            'timezone' => ['sometimes', 'string', 'max:80', 'timezone'],
            'date_format' => ['sometimes', Rule::in(['dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'])],
            'time_format' => ['sometimes', Rule::in(['12h', '24h'])],
            'default_theme' => ['sometimes', Rule::in(['system', 'light', 'dark'])],
            'invoice_paper_size' => [
                'sometimes', Rule::in(['letter', 'a4', 'thermal_80mm', 'thermal_58mm']),
            ],
            'country_phone_code' => ['sometimes', 'string', 'max:10', 'regex:/^\+[1-9][0-9]{0,5}$/'],
            'decimal_places' => ['sometimes', 'integer', 'between:0,4'],
            'enable_sound_alerts' => ['sometimes', 'boolean'],
            'receipt_footer' => ['sometimes', 'nullable', 'string', 'max:2000'],
        ]);

        if ($data === []) {
            return response()->json(['message' => 'No se recibieron preferencias para guardar.'], 422);
        }

        DB::transaction(function () use ($company, $data): void {
            // Serializar el primer INSERT cuando varias solicitudes actualizan la misma empresa.
            DB::table('companies')->where('id', $company)->lockForUpdate()->first(['id']);
            $existing = DB::table('company_preferences')
                ->where('company_id', $company)->first(['id']);

            if ($existing !== null) {
                DB::table('company_preferences')->where('id', $existing->id)
                    ->where('company_id', $company)
                    ->update(array_merge($data, ['updated_at' => now()]));
            } else {
                DB::table('company_preferences')->insert(array_merge(
                    ['company_id' => $company, 'created_at' => now(), 'updated_at' => now()],
                    $data
                ));
            }
        });

        return response()->json([
            'message' => 'Preferencias empresariales guardadas.',
            'preferences' => $this->normalizedPreferences($company),
        ]);
    }
}