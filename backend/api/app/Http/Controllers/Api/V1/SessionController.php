<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

class SessionController extends Controller
{
    public function token(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'string', 'max:100'],
        ]);

        $user = User::query()
            ->where('email', mb_strtolower($data['email']))
            ->first();

        if (!$user || !Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['Credenciales incorrectas.'],
            ]);
        }

        $authorized = DB::table('company_user')
            ->join(
                'companies',
                'companies.id',
                '=',
                'company_user.company_id'
            )
            ->where('company_user.user_id', $user->id)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)
            ->exists();

        // Acceso de usuarios bloqueado si el periodo de gracia ya vencio.
        $eligibleIds = DB::table('company_user')->where('user_id', $user->id)
            ->where('status', 'active')->pluck('company_id');
        $billingAllowed = $eligibleIds->contains(fn ($id) =>
            \App\Support\MasterBilling24N8::allowed((int) $id));
        if (!$authorized || !$billingAllowed) {

            return response()->json([
                'message' => 'No tienes acceso a una empresa activa.',
            ], 403);
        }

        // Rechazar autenticación web/escritorio a lavadores. El nombre de dispositivo es
        // un control adicional; la verificación fuerte requiere atestación de aplicación.
        $washer = DB::table('company_user')->where('user_id',$user->id)->where('status','active')
            ->pluck('company_id')->contains(fn ($companyId) =>
                \App\Support\WasherAccess24N3::isWasher((int)$companyId,(int)$user->id));
        if ($washer && !in_array($data['device_name'], ['adn-mycarwash-android','adn-mycarwash-ios'], true)) {
            return response()->json(['message' => 'Esta cuenta solo permite acceso desde la aplicación móvil.'],403);
        }

        $token = $user->createToken(
            $data['device_name'],
            ['*'],
            now()->addDays(30)
        );

        return response()->json([
            'message' => 'Autenticacion correcta.',
            'token_type' => 'Bearer',
            'access_token' => $token->plainTextToken,
            'expires_at' => now()->addDays(30)->toIso8601String(),
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
            ],
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();

        $companies = DB::table('company_user')
            ->join(
                'companies',
                'companies.id',
                '=',
                'company_user.company_id'
            )
            ->where('company_user.user_id', $user->id)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)
            ->select(
                'companies.id',
                'companies.name',
                'companies.slug',
                'company_user.access_all_branches'
            )
            ->orderBy('companies.name')
            ->get();

        $companies = $companies->filter(fn ($company) =>
            \App\Support\MasterBilling24N8::allowed((int) $company->id))->values();

        $companies = $companies->map(function ($company) use ($user) {

            $roleIds = DB::table('user_roles')->where('company_id', $company->id)
                ->where('user_id', $user->id)->pluck('role_id');
            $company->permissions = DB::table('role_permission as rp')
                ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
                ->whereIn('rp.role_id', $roleIds)->where('p.code', 'like', 'nav.%')
                ->pluck('p.code')->unique()->values()->all();
            $company->is_washer = \App\Support\WasherAccess24N3::isWasher((int) $company->id, (int) $user->id);
            $company->legacy_full_access = DB::table('roles')->whereIn('id', $roleIds)
                ->where('code', 'owner')->where('is_system', true)->exists()
                || ($company->permissions === [] && !$company->is_washer);
            return $company;
        });

        return response()->json([
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
            ],
            'companies' => $companies,
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->user()->currentAccessToken();

        if ($token instanceof PersonalAccessToken) {
            $token->delete();
        }

        return response()->json([
            'message' => 'Sesion de token finalizada.',
        ]);
    }
}