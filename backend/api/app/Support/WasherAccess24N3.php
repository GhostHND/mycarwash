<?php

namespace App\Support;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** Scope of an employee account, never derived from a client supplied employee_id. */
final class WasherAccess24N3
{
    public static function isOwner(int $company, int $user): bool
    {
        return DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->where('ur.company_id', $company)->where('ur.user_id', $user)
          ->where('r.code', 'owner')->exists();
    }

    public static function isWasher(int $company, int $user): bool
    {
        if (self::isOwner($company, $user)) return false;
        // Compatibilidad con pruebas historicas que construyen esquemas reducidos.
        // En produccion estas dos tablas y la columna position siempre existen.
        if (Schema::hasTable('employee_user') && Schema::hasColumn('employees', 'position')) {
            $employee = DB::table('employee_user as eu')->join('employees as e', function ($join): void {
                $join->on('e.id', '=', 'eu.employee_id')->on('e.company_id', '=', 'eu.company_id');
            })->where('eu.company_id', $company)->where('eu.user_id', $user)->value('e.position');
            if (strtolower((string) $employee) === 'washer') return true;
        }
        // Also protect misconfigured accounts with a washer role but no employee link.
        return DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->where('ur.company_id', $company)->where('ur.user_id', $user)
          ->where(function ($query): void {
              $query->whereRaw('LOWER(r.name) LIKE ?', ['%lavador%'])
                    ->orWhereRaw('LOWER(r.name) LIKE ?', ['%washer%'])
                    ->orWhere('r.code', 'washer');
          })->exists();
    }

    public static function employeeId(int $company, int $user): int
    {
        $id = DB::table('employee_user as eu')->join('employees as e', function ($join): void {
            $join->on('e.id', '=', 'eu.employee_id')->on('e.company_id', '=', 'eu.company_id');
        })->where('eu.company_id', $company)->where('eu.user_id', $user)
          ->where('e.is_active', true)->whereNull('e.deleted_at')
          ->where('e.position', 'washer')->value('e.id');
        abort_unless($id, 403, 'La cuenta no está vinculada a un lavador activo.');
        return (int) $id;
    }

    public static function assigned(int $company, int $employee, int $order): bool
    {
        return DB::table('wash_assignments')->where('company_id', $company)
            ->where('employee_id', $employee)->where('order_id', $order)
            ->where('is_active', true)->exists();
    }
}
