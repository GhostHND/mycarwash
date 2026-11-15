<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rules\File;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Throwable;

class BusinessLogoController extends Controller
{
    private function authorizeCompany(
        Request $request,
        int $company,
        string $permission
    ): void {
        $userId = $request->user()->id;

        $member = DB::table('company_user')
            ->join(
                'companies',
                'companies.id',
                '=',
                'company_user.company_id'
            )
            ->where('company_user.user_id', $userId)
            ->where('company_user.company_id', $company)
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

        abort_unless(
            $allowed,
            403,
            'No tienes permiso para modificar esta empresa.'
        );
    }

    private function path(int $company): ?string
    {
        return DB::table('company_brandings')
            ->where('company_id', $company)
            ->value('business_logo_path');
    }

    private function deleteOwnedFile(
        int $company,
        ?string $path
    ): void {
        $prefix = 'mycarwash/companies/' . $company . '/logos/';

        if ($path !== null && str_starts_with($path, $prefix)) {
            Storage::disk('local')->delete($path);
        }
    }

    public function show(
        Request $request,
        int $company
    ): BinaryFileResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.view'
        );

        $path = $this->path($company);
        $disk = Storage::disk('local');

        abort_if(
            $path === null || !$disk->exists($path),
            404,
            'La empresa no tiene un logotipo cargado.'
        );

        $mime = $disk->mimeType($path);

        abort_unless(
            in_array(
                $mime,
                ['image/png', 'image/jpeg', 'image/webp'],
                true
            ),
            415,
            'Formato no admitido.'
        );

        return response()->file(
            $disk->path($path),
            [
                'Content-Type' => $mime,
                'Cache-Control' => 'private, no-store',
                'X-Content-Type-Options' => 'nosniff',
            ]
        );
    }

    public function upload(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.branding.manage'
        );

        $request->validate([
            'logo' => [
                'required',
                File::image()
                    ->types(['png', 'jpg', 'jpeg', 'webp'])
                    ->max('2mb'),
                'extensions:png,jpg,jpeg,webp',
                'dimensions:max_width=5000,max_height=5000',
            ],
        ]);

        $file = $request->file('logo');

        $directory = 'mycarwash/companies/'
            . $company
            . '/logos';

        $newPath = $file->store($directory, 'local');

        if (!$newPath) {
            return response()->json([
                'message' => 'No se pudo guardar el archivo.',
            ], 500);
        }

        $oldPath = $this->path($company);

        try {
            DB::transaction(function () use ($company, $newPath) {

                $exists = DB::table('company_brandings')
                    ->where('company_id', $company)
                    ->exists();

                if ($exists) {
                    DB::table('company_brandings')
                        ->where('company_id', $company)
                        ->update([
                            'business_logo_path' => $newPath,
                            'updated_at' => now(),
                        ]);
                } else {
                    DB::table('company_brandings')->insert([
                        'company_id' => $company,
                        'business_logo_path' => $newPath,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            });
        } catch (Throwable $error) {
            Storage::disk('local')->delete($newPath);
            throw $error;
        }

        $this->deleteOwnedFile($company, $oldPath);

        return response()->json([
            'message' => 'Logotipo empresarial actualizado.',
            'has_business_logo' => true,
        ], 201);
    }

    public function remove(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.branding.manage'
        );

        $oldPath = $this->path($company);

        DB::table('company_brandings')
            ->where('company_id', $company)
            ->update([
                'business_logo_path' => null,
                'updated_at' => now(),
            ]);

        $this->deleteOwnedFile($company, $oldPath);

        return response()->json([
            'message' => 'Logotipo empresarial eliminado.',
            'has_business_logo' => false,
        ]);
    }
}