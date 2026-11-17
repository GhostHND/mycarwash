<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Versioned, company/branch-scoped POS document design; fiscal values never enter this payload. */
class CompanyPosDocumentTemplateController extends Controller
{
    public const BLOCKS = ['logo', 'brand', 'document', 'fiscal', 'sale', 'customer', 'items', 'totals', 'payments', 'notes', 'footer'];
    private const REQUIRED = ['document', 'sale', 'customer', 'items', 'totals'];

    private function access(Request $request, int $company, string $permission): void
    {
        $uid = (int) $request->user()->id;
        if (!DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $uid)
            ->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente.');
    }

    private function validateBranch(int $company, int $branch): void
    {
        if (!DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible.']);
        }
    }

    public static function defaults(string $type): array
    {
        return [
            'title' => $type === 'FISCAL_INVOICE' ? 'FACTURA' : 'RECIBO DE COMPRA',
            'subtitle' => 'Gracias por su compra',
            'brand_name' => '',
            'footer_text' => 'Gracias por preferirnos',
            'custom_note' => '',
            'primary_color' => '#0FA7B4',
            'text_color' => '#202B30',
            'background_color' => '#FFFFFF',
            'font_family' => 'helvetica',
            'font_size' => 10,
            'heading_size' => 17,
            'alignment' => 'center',
            'paper' => $type === 'FISCAL_INVOICE' ? 'A4' : '80MM',
            'logo_base64' => '',
            'logo_width_mm' => 32,
            'show_sku' => false,
            'show_phone' => true,
            'show_email' => false,
            'show_address' => false,
            'show_payment_details' => true,
            'show_separators' => true,
            'sections' => self::BLOCKS,
            'hidden_sections' => [],
        ];
    }

    public function show(Request $request, int $company): JsonResponse
    {
        $this->access($request, $company, 'company.view');
        $data = $request->validate([
            'branch_id' => ['required', 'integer', 'min:1'],
            'document_type' => ['required', 'in:RECEIPT,FISCAL_INVOICE'],
        ]);
        $branch = (int) $data['branch_id'];
        $this->validateBranch($company, $branch);
        $record = DB::table('pos_document_template_revisions')
            ->where('company_id', $company)->where('branch_id', $branch)
            ->where('document_type', $data['document_type'])->orderByDesc('revision')->first();
        return response()->json(['data' => [
            'document_type' => $data['document_type'],
            'branch_id' => $branch,
            'revision' => (int) ($record?->revision ?? 0),
            'design' => $record ? json_decode($record->design_json, true, 512, JSON_THROW_ON_ERROR)
                : self::defaults($data['document_type']),
            'saved' => $record !== null,
        ]]);
    }

    public function save(Request $request, int $company): JsonResponse
    {
        $this->access($request, $company, 'company.update');
        $data = $request->validate([
            'branch_id' => ['required', 'integer', 'min:1'],
            'document_type' => ['required', 'in:RECEIPT,FISCAL_INVOICE'],
            'expected_revision' => ['required', 'integer', 'min:0'],
            'design' => ['required', 'array'],
            'design.title' => ['required', 'string', 'max:90'],
            'design.subtitle' => ['present', 'nullable', 'string', 'max:140'],
            'design.brand_name' => ['present', 'nullable', 'string', 'max:140'],
            'design.footer_text' => ['present', 'nullable', 'string', 'max:350'],
            'design.custom_note' => ['present', 'nullable', 'string', 'max:350'],
            'design.primary_color' => ['required', 'regex:/^#[0-9A-Fa-f]{6}$/D'],
            'design.text_color' => ['required', 'regex:/^#[0-9A-Fa-f]{6}$/D'],
            'design.background_color' => ['required', 'regex:/^#[0-9A-Fa-f]{6}$/D'],
            'design.font_family' => ['required', 'in:helvetica,times,courier'],
            'design.font_size' => ['required', 'integer', 'between:8,16'],
            'design.heading_size' => ['required', 'integer', 'between:12,32'],
            'design.alignment' => ['required', 'in:left,center,right'],
            'design.paper' => ['required', 'in:58MM,80MM,A4,LETTER'],
            'design.logo_base64' => ['present', 'nullable', 'string', 'max:1398104'],
            'design.logo_width_mm' => ['required', 'integer', 'between:10,80'],
            'design.show_sku' => ['required', 'boolean'],
            'design.show_phone' => ['required', 'boolean'],
            'design.show_email' => ['required', 'boolean'],
            'design.show_address' => ['required', 'boolean'],
            'design.show_payment_details' => ['required', 'boolean'],
            'design.show_separators' => ['required', 'boolean'],
            'design.sections' => ['required', 'array', 'size:11'],
            'design.sections.*' => ['required', 'string', 'in:logo,brand,document,fiscal,sale,customer,items,totals,payments,notes,footer', 'distinct'],
            'design.hidden_sections' => ['present', 'array', 'max:6'],
            'design.hidden_sections.*' => ['required', 'string', 'in:logo,brand,notes,footer', 'distinct'],
        ]);
        $branch = (int) $data['branch_id'];
        $this->validateBranch($company, $branch);
        $design = $data['design'];
        $unknown = array_diff(array_keys($design), array_keys(self::defaults($data['document_type'])));
        if ($unknown !== []) {
            throw ValidationException::withMessages(['design' => 'Campos desconocidos en la plantilla.']);
        }
        // ConvertEmptyStringsToNull de Laravel normaliza cadenas vacías a null;
        // el modelo visual utiliza '' para campos opcionales.
        foreach (['subtitle','brand_name','footer_text','custom_note','logo_base64'] as $field) {
            $design[$field] = (string) ($design[$field] ?? '');
        }
        $logo = $design['logo_base64'];
        if ($logo !== '') {
            $bytes = base64_decode($logo, true);
            if ($bytes === false || strlen($bytes) > 1048576 || strlen($bytes) < 8) {
                throw ValidationException::withMessages(['design.logo_base64' => 'Logo PNG/JPEG de máximo 1 MB.']);
            }
            $info = @getimagesizefromstring($bytes);
            if ($info === false || !in_array($info[2], [IMAGETYPE_PNG, IMAGETYPE_JPEG], true)
                || $info[0] > 2400 || $info[1] > 2400) {
                throw ValidationException::withMessages(['design.logo_base64' => 'Logo PNG/JPEG inválido o demasiado grande.']);
            }
        }
        $saved = DB::transaction(function () use ($request, $company, $branch, $data, $design): int {
            // Lock company row so concurrent writers cannot assign the same revision.
            DB::table('companies')->where('id', $company)->lockForUpdate()->first();
            $previous = DB::table('pos_document_template_revisions')
                ->where('company_id', $company)->where('branch_id', $branch)
                ->where('document_type', $data['document_type'])->orderByDesc('revision')->first();
            $current = (int) ($previous?->revision ?? 0);
            if ($current !== (int) $data['expected_revision']) {
                abort(409, 'La plantilla cambió en otra sesión. Actualiza antes de guardar.');
            }
            DB::table('pos_document_template_revisions')->insert([
                'company_id' => $company, 'branch_id' => $branch,
                'document_type' => $data['document_type'],
                'revision' => $current + 1,
                'design_json' => json_encode($design, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE),
                'author_user_id' => $request->user()->id,
                'created_at' => now(), 'updated_at' => now(),
            ]);
            return $current + 1;
        });
        return response()->json(['data' => ['revision' => $saved, 'saved' => true]], 201);
    }
}
