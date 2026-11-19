<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/** Permisos por modulo y accion para las rutas existentes y las nuevas. */
class CompanyModuleAccess24N2
{
    public function handle(Request $request, Closure $next): Response
    {
        $company = (int) ($request->route('company') ?? 0);
        if ($company <= 0 || !$request->user()) return $next($request);
        $userId = (int) $request->user()->id;
        $active = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        abort_unless($active, 403, 'Cuenta o empresa desactivada.');
        $roleRows = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->where('ur.company_id', $company)->where('ur.user_id', $userId)->get(['r.id', 'r.code', 'r.is_system']);
        abort_if($roleRows->isEmpty(), 403, 'Sin rol para esta empresa.');
        if ($roleRows->contains(fn ($r) => $r->code === 'owner' && (bool) $r->is_system)) return $next($request);
        $ids = $roleRows->pluck('id')->toArray();
        $permissions = DB::table('role_permission as rp')->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->whereIn('rp.role_id', $ids)->where('p.code', 'like', 'nav.%')->pluck('p.code')->toArray();
        // Compatibilidad con roles historicos; roles nuevos se crean siempre con matriz nav.*.
        if ($permissions === []) return $next($request);
        $path = (string) $request->route()->uri();
        $path = preg_replace('~^(?:api/)?v1/companies/\{company\}/?~', '', $path);
        $segment = explode('/', $path)[0] ?? '';
        $module = match ($segment) {
            'users', 'roles' => 'users',
            'dashboard' => 'dashboard',
            'workflow', 'services', 'monitor-theme-24b' => 'washes',
            'schedule' => in_array(explode('/', $path)[1] ?? '', ['shifts', 'roster'], true) ? 'staff' : 'schedule',
            'special-hours' => 'company',
            'clients', 'vehicles' => 'customers',
            'employees' => 'staff',
            'inventory', 'purchasing' => 'inventory',
            'cash', 'finance' => 'cash',
            'sales', 'pos' => 'sales',
            'reports' => 'reports',
            'media' => match (explode('/', $path)[1] ?? '') {
                'employees' => 'staff', 'items' => 'inventory', default => 'customers',
            },
            default => 'company',
        };
        $method = $request->method();
        $action = match ($method) {
            'GET', 'HEAD' => 'view', 'POST' => 'create', default => 'edit',
        };
        if ($method === 'POST' && (preg_match('~(?:checkout|transition|receive|cancel|close|open|assign|initialize|transfer|reminder-read)~', $path) || $path === 'pos/sales')) {
            $action = 'execute';
        }
        // Los controladores exigen ademas users.manage / roles.manage.
        abort_unless(in_array("nav.$module.$action", $permissions, true), 403,
            'No tienes permiso para esta accion en '.$module.'.');
        return $next($request);
    }
}
