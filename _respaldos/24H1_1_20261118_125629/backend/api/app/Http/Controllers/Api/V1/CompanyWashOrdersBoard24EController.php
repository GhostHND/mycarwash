<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class CompanyWashOrdersBoard24EController extends Controller
{
    public function index(Request $request, int $company): JsonResponse
    {
        $userId = (int) $request->user()->id;
        $member = DB::table('company_user')
            ->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)
            ->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $permission = DB::table('user_roles as ur')
            ->join('roles as r', function ($join): void {
                $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
            })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', 'company.view')->exists();
        if (!$permission) abort(403, 'Sin permiso para consultar las órdenes.');

        $input = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:120'],
            'status' => ['sometimes', Rule::in(['TODAS','EN_ESPERA','ASIGNADO','EN_PROCESO','TERMINADO','ENTREGADO','CANCELADO'])],
            'branch_id' => ['sometimes', 'integer', 'min:1'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'between:1,30'],
        ]);
        $branchId = $input['branch_id'] ?? null;
        if ($branchId !== null && !DB::table('branches')->where('company_id', $company)->where('id', $branchId)->exists()) {
            abort(422, 'Sucursal no válida.');
        }
        $base = DB::table('wash_orders as o')->where('o.company_id', $company);
        if ($branchId !== null) $base->where('o.branch_id', $branchId);
        $rawCounts = (clone $base)->select('o.status', DB::raw('COUNT(*) as total'))
            ->groupBy('o.status')->pluck('total', 'status')->toArray();

        $query = (clone $base)
            ->leftJoin('vehicles as v', function ($join): void {
                $join->on('v.id', '=', 'o.vehicle_id')->on('v.company_id', '=', 'o.company_id');
            })
            ->leftJoin('clients as c', function ($join): void {
                $join->on('c.id', '=', 'v.client_id')->on('c.company_id', '=', 'o.company_id');
            })
            ->leftJoin('wash_services as s', function ($join): void {
                $join->on('s.id', '=', 'o.service_id')->on('s.company_id', '=', 'o.company_id');
            })
            ->leftJoin('wash_bays as b', function ($join): void {
                $join->on('b.id', '=', 'o.bay_id')->on('b.company_id', '=', 'o.company_id');
            });
        if (isset($input['status']) && $input['status'] !== 'TODAS') {
            $query->where('o.status', $input['status']);
        }
        $q = trim((string) ($input['q'] ?? ''));
        if ($q !== '') {
            $like = '%'.addcslashes($q, '%_\\').'%';
            $query->where(function ($builder) use ($like): void {
                $builder->where('o.tracking_code', 'like', $like)
                    ->orWhere('v.plate', 'like', $like)
                    ->orWhere('v.brand', 'like', $like)
                    ->orWhere('v.model', 'like', $like)
                    ->orWhere('c.full_name', 'like', $like)
                    ->orWhere('s.name', 'like', $like);
            });
        }
        $page = $query->select('o.*', 'v.plate', 'v.brand', 'v.model',
            'c.full_name as client_name', 's.name as service_name', 'b.name as bay_name')
            ->orderByDesc('o.id')->paginate($input['per_page'] ?? 9)->toArray();
        $ids = array_map(fn ($row) => (int) $row->id, $page['data']);
        $assignments = empty($ids) ? collect() : DB::table('wash_assignments as a')
            ->join('employees as e', function ($join): void {
                $join->on('e.id', '=', 'a.employee_id')->on('e.company_id', '=', 'a.company_id');
            })->where('a.company_id', $company)->whereIn('a.order_id', $ids)
            ->where('a.is_active', true)->select('a.order_id', 'e.full_name')
            ->orderBy('a.id')->get()->groupBy('order_id');
        $page['data'] = array_map(function ($row) use ($assignments): array {
            $item = (array) $row;
            $item['vehicle_label'] = trim((string) ($row->brand ?? '').' '.(string) ($row->model ?? ''));
            $item['washer_names'] = ($assignments->get($row->id) ?? collect())
                ->pluck('full_name')->values()->toArray();
            return $item;
        }, $page['data']);
        $page['summary'] = [
            'scope' => $branchId === null ? 'Todas las sucursales · Historial' : 'Sucursal seleccionada · Historial',
            'new' => (int) ($rawCounts['EN_ESPERA'] ?? 0),
            'waiting' => (int) ($rawCounts['ASIGNADO'] ?? 0),
            'active' => (int) ($rawCounts['EN_PROCESO'] ?? 0),
            'finished' => (int) ($rawCounts['TERMINADO'] ?? 0),
        ];
        return response()->json($page);
    }
}
