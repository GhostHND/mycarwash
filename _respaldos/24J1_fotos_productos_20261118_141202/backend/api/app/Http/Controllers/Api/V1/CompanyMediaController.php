<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/** Fotografias privadas, asociadas a un vehiculo o a un empleado de la empresa. */
class CompanyMediaController extends Controller
{
    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'No tienes permiso para esta operación.');
    }

    private function entity(int $company, string $kind, int $record): void
    {
        $table = match ($kind) {
            'vehicles' => 'vehicles',
            'employees' => 'employees',
            default => abort(404),
        };
        if (!DB::table($table)->where('id', $record)->where('company_id', $company)
            ->whereNull('deleted_at')->exists()) abort(404, 'Registro no disponible.');
    }

    private function asset(int $company, string $kind, int $record): ?object
    {
        return DB::table('company_entity_photos as p')
            ->join('company_media_assets as a', function ($join): void {
                $join->on('a.id', '=', 'p.media_asset_id')
                    ->on('a.company_id', '=', 'p.company_id');
            })
            ->where('p.company_id', $company)
            ->where('p.owner_type', $kind)->where('p.owner_id', $record)
            ->select('p.id as photo_link_id', 'p.show_on_kiosk',
                'a.id as asset_id', 'a.disk', 'a.path', 'a.mime_type',
                'a.file_size')->first();
    }

    private function summary(int $company, string $kind, int $record, ?object $asset): array
    {
        return [
            'exists' => $asset !== null,
            'show_on_kiosk' => (bool) ($asset?->show_on_kiosk ?? false),
            'mime_type' => $asset?->mime_type,
            'bytes' => $asset?->file_size,
            'url' => $asset === null ? null : "/api/v1/companies/$company/media/$kind/$record/file",
        ];
    }

    public function show(Request $request, int $company, string $kind, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $this->entity($company, $kind, $record);
        return response()->json(['data' => $this->summary($company, $kind, $record, $this->asset($company, $kind, $record))]);
    }

    public function file(Request $request, int $company, string $kind, int $record): Response
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $this->entity($company, $kind, $record);
        $asset = $this->asset($company, $kind, $record);
        if (!$asset || $asset->disk !== 'local' || !Storage::disk('local')->exists($asset->path)) abort(404);
        return response(Storage::disk('local')->get($asset->path), 200, [
            'Content-Type' => $asset->mime_type ?? 'application/octet-stream',
            'Cache-Control' => 'private, no-store',
            'Content-Disposition' => 'inline',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    public function store(Request $request, int $company, string $kind, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->entity($company, $kind, $record);
        $input = $request->validate([
            'photo' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:2048'],
            'show_on_kiosk' => ['sometimes', 'boolean'],
        ]);
        $file = $request->file('photo');
        $mime = (string) $file->getMimeType();
        if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
            throw ValidationException::withMessages(['photo' => 'Formato de imagen no permitido.']);
        }
        $bytes = $file->getSize();
        if (!$bytes || $bytes > 2097152) {
            throw ValidationException::withMessages(['photo' => 'Imagen vacía o demasiado grande (máximo 2 MB).']);
        }
        $ext = match ($mime) { 'image/png' => 'png', 'image/webp' => 'webp', default => 'jpg' };
        $path = 'mycarwash/'.$company.'/'.$kind.'/'.$record.'/'.Str::uuid().'.'.$ext;
        $previous = $this->asset($company, $kind, $record);
        $written = Storage::disk('local')->put($path, file_get_contents($file->getRealPath()));
        if (!$written) abort(500, 'No se pudo guardar la fotografía.');
        try {
            DB::transaction(function () use ($company, $kind, $record, $path, $mime, $bytes, $input, $previous, $file): void {
                $show = $input['show_on_kiosk'] ?? ($previous?->show_on_kiosk ?? false);
                $metadata = [
                    'category' => $kind === 'vehicles' ? 'vehicle_photo' : 'employee_photo',
                    'disk' => 'local', 'path' => $path,
                    'original_filename' => mb_substr(basename($file->getClientOriginalName()), 0, 255),
                    'mime_type' => $mime, 'file_size' => $bytes,
                    'alt_text' => null, 'is_public' => false, 'sort_order' => 0,
                    'updated_at' => now(),
                ];
                if ($previous) {
                    // Una foto por entidad; reutilizar su registro de biblioteca.
                    DB::table('company_media_assets')->where('id', $previous->asset_id)
                        ->where('company_id', $company)->update($metadata);
                    DB::table('company_entity_photos')->where('id', $previous->photo_link_id)
                        ->where('company_id', $company)
                        ->update(['show_on_kiosk' => (bool) $show, 'updated_at' => now()]);
                } else {
                    $assetId = DB::table('company_media_assets')->insertGetId($metadata + [
                        'company_id' => $company, 'created_at' => now(),
                    ]);
                    DB::table('company_entity_photos')->insert([
                        'company_id' => $company, 'owner_type' => $kind,
                        'owner_id' => $record, 'media_asset_id' => $assetId,
                        'show_on_kiosk' => (bool) $show,
                        'created_at' => now(), 'updated_at' => now(),
                    ]);
                }
            });
        } catch (\Throwable $error) {
            Storage::disk('local')->delete($path);
            throw $error;
        }
        if ($previous && $previous->disk === 'local' && $previous->path !== $path) {
            Storage::disk('local')->delete($previous->path);
        }
        return response()->json(['message' => 'Fotografía guardada.', 'data' => $this->summary($company, $kind, $record, $this->asset($company, $kind, $record))], 201);
    }

    public function update(Request $request, int $company, string $kind, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->entity($company, $kind, $record);
        $input = $request->validate(['show_on_kiosk' => ['required', 'boolean']]);
        $asset = $this->asset($company, $kind, $record);
        if (!$asset) abort(404, 'Primero agrega una fotografía.');
        DB::table('company_entity_photos')->where('id', $asset->photo_link_id)
            ->where('company_id', $company)->update([
            'show_on_kiosk' => $input['show_on_kiosk'], 'updated_at' => now(),
        ]);
        return response()->json(['message' => 'Visibilidad actualizada.', 'data' => $this->summary($company, $kind, $record, $this->asset($company, $kind, $record))]);
    }

    public function destroy(Request $request, int $company, string $kind, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->entity($company, $kind, $record);
        $asset = $this->asset($company, $kind, $record);
        if (!$asset) abort(404);
        DB::transaction(function () use ($company, $asset): void {
            DB::table('company_entity_photos')->where('id', $asset->photo_link_id)
                ->where('company_id', $company)->delete();
            DB::table('company_media_assets')->where('id', $asset->asset_id)
                ->where('company_id', $company)->delete();
        });
        if ($asset->disk === 'local') Storage::disk('local')->delete($asset->path);
        return response()->json(['message' => 'Fotografía eliminada.']);
    }
}
