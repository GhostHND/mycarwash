<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

final class CompanyMonitorTheme24BController extends Controller
{
    private const COLORS = [
        'primary_color' => '#00DCE5',
        'secondary_color' => '#0B292F',
        'accent_color' => '#00DCE5',
        'background_color' => '#050C0F',
        'surface_color' => '#071E23',
        'text_color' => '#F4F7F8',
        'muted_text_color' => '#A5B6BB',
        'sidebar_color' => '#0B292F',
        'button_color' => '#00DCE5',
        'success_color' => '#00D99A',
        'warning_color' => '#F59E0B',
        'danger_color' => '#EC488A',
        'border_color' => '#00DCE5',
        'queue_color' => '#073039',
    ];

    private function permit(Request $request, int $company, string $permission): void
    {
        $id = $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $id)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        abort_unless($member, 404, 'Empresa no disponible');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $id)
            ->where('p.code', $permission)->exists();
        abort_unless($allowed, 403, 'Permiso insuficiente');
    }

    private function saved(int $company): array
    {
        $json = DB::table('company_monitor_themes')->where('company_id', $company)->value('colors');
        $parsed = $json ? json_decode((string) $json, true) : [];
        return array_merge(self::COLORS, is_array($parsed) ? array_intersect_key($parsed, self::COLORS) : []);
    }

    public function show(Request $request, int $company): JsonResponse
    {
        $this->permit($request, $company, 'company.view');
        return response()->json(['colors' => $this->saved($company)]);
    }

    public function update(Request $request, int $company): JsonResponse
    {
        $this->permit($request, $company, 'company.branding.manage');
        $input = $request->all();
        if ($input === [] || array_diff(array_keys($input), array_keys(self::COLORS)) !== []) {
            return response()->json(['message' => 'Campos de color incorrectos'], 422);
        }
        $rules = array_fill_keys(array_keys(self::COLORS), ['sometimes', 'required', 'regex:/^#[0-9a-fA-F]{6}$/']);
        $data = Validator::make($input, $rules)->validate();
        DB::transaction(function () use ($company, $data): void {
            DB::table('companies')->where('id', $company)->lockForUpdate()->first(['id']);
            $colors = array_merge($this->saved($company), $data);
            $existing = DB::table('company_monitor_themes')->where('company_id', $company)->exists();
            if ($existing) {
                DB::table('company_monitor_themes')->where('company_id', $company)
                    ->update(['colors' => json_encode($colors), 'updated_at' => now()]);
            } else {
                DB::table('company_monitor_themes')->insert([
                    'company_id' => $company, 'colors' => json_encode($colors),
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        });
        return response()->json(['colors' => $this->saved($company)]);
    }
}
