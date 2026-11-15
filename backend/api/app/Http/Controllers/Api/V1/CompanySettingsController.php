<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class CompanySettingsController extends Controller
{
    private function authorizeCompany(
        Request $request,
        int $companyId,
        string $permission
    ): void {
        $userId = $request->user()->id;

        $membership = DB::table('company_user')
            ->join(
                'companies',
                'companies.id',
                '=',
                'company_user.company_id'
            )
            ->where('company_user.company_id', $companyId)
            ->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)
            ->exists();

        if (!$membership) {
            abort(404, 'Empresa no disponible.');
        }

        $allowed = DB::table('user_roles as ur')
            ->join('roles as r', function ($join) {
                $join->on('r.id', '=', 'ur.role_id')
                    ->on('r.company_id', '=', 'ur.company_id');
            })
            ->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $companyId)
            ->where('ur.user_id', $userId)
            ->where('p.code', $permission)
            ->exists();

        if (!$allowed) {
            abort(403, 'No tienes permiso para esta operación.');
        }
    }

    public function show(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');

        return response()->json([
            'company' => DB::table('companies')
                ->where('id', $company)
                ->first(['id', 'name', 'slug']),
            'profile' => DB::table('company_profiles')
                ->where('company_id', $company)
                ->first(),
            'branding' => DB::table('company_brandings')
                ->where('company_id', $company)
                ->first(),
            'preferences' => DB::table('company_preferences')
                ->where('company_id', $company)
                ->first(),
        ]);
    }

    public function updateProfile(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany($request, $company, 'company.update');

        $data = $request->validate([
            'commercial_name' => ['sometimes', 'nullable', 'string', 'max:180'],
            'business_category' => ['sometimes', 'nullable', 'string', 'max:120'],
            'business_type' => ['sometimes', 'nullable', 'string', 'max:100'],
            'slogan' => ['sometimes', 'nullable', 'string', 'max:255'],
            'public_email' => ['sometimes', 'nullable', 'email', 'max:190'],
            'support_email' => ['sometimes', 'nullable', 'email', 'max:190'],
            'website_url' => ['sometimes', 'nullable', 'url', 'max:500'],
            'legal_representative' => ['sometimes', 'nullable', 'string', 'max:180'],
            'registration_number' => ['sometimes', 'nullable', 'string', 'max:100'],
            'founded_at' => ['sometimes', 'nullable', 'date'],
            'short_description' => ['sometimes', 'nullable', 'string', 'max:3000'],
            'description' => ['sometimes', 'nullable', 'string', 'max:20000'],
            'history' => ['sometimes', 'nullable', 'string', 'max:20000'],
            'mission' => ['sometimes', 'nullable', 'string', 'max:10000'],
            'vision' => ['sometimes', 'nullable', 'string', 'max:10000'],
            'business_values' => ['sometimes', 'nullable', 'string', 'max:10000'],
        ]);

        if (count($data) === 0) {
            return response()->json([
                'message' => 'No se recibieron campos válidos.',
            ], 422);
        }

        $this->saveSingleRecord('company_profiles', $company, $data);

        return response()->json([
            'message' => 'Información empresarial guardada.',
            'profile' => DB::table('company_profiles')
                ->where('company_id', $company)
                ->first(),
        ]);
    }

    public function updateBranding(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.branding.manage'
        );

        $colorRules = [
            'sometimes',
            'regex:/^#[0-9A-Fa-f]{6}$/',
        ];

        $rules = [];

        foreach ([
            'primary_color',
            'secondary_color',
            'accent_color',
            'background_color',
            'surface_color',
            'text_color',
            'muted_text_color',
            'sidebar_color',
            'button_color',
            'success_color',
            'warning_color',
            'danger_color',
        ] as $field) {
            $rules[$field] = $colorRules;
        }

        $rules['font_family'] = ['prohibited'];

        $rules['button_style'] = [
            'sometimes',
            Rule::in(['rounded', 'square', 'pill']),
        ];

        $rules['sidebar_style'] = [
            'sometimes',
            Rule::in(['expanded', 'compact']),
        ];

        $rules['border_radius'] = [
            'sometimes', 'integer', 'between:0,40',
        ];

        $rules['compact_mode'] = ['sometimes', 'boolean'];
        $rules['show_business_name'] = ['sometimes', 'boolean'];

        $data = $request->validate($rules);

        if (count($data) === 0) {
            return response()->json([
                'message' => 'No se recibieron cambios de apariencia.',
            ], 422);
        }

        // Los logos oficiales ADN no son configurables
        // desde esta API.

        $this->saveSingleRecord('company_brandings', $company, $data);

        return response()->json([
            'message' => 'Apariencia empresarial guardada.',
            'branding' => DB::table('company_brandings')
                ->where('company_id', $company)
                ->first(),
        ]);
    }

    private function saveSingleRecord(
        string $table,
        int $company,
        array $data
    ): void {
        DB::transaction(function () use ($table, $company, $data) {
            $exists = DB::table($table)
                ->where('company_id', $company)
                ->exists();

            if ($exists) {
                DB::table($table)
                    ->where('company_id', $company)
                    ->update(array_merge($data, [
                        'updated_at' => now(),
                    ]));
            } else {
                DB::table($table)->insert(
                    array_merge($data, [
                        'company_id' => $company,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ])
                );
            }
        });
    }

    public function contacts(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');

        $data = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
        ]);

        $search = trim($data['q'] ?? '');

        $query = DB::table('company_contacts')
            ->where('company_id', $company);

        if ($search !== '') {
            $digits = preg_replace('/\D+/', '', $search);
            $like = '%' . $search . '%';

            $query->where(function ($builder) use (
                $search,
                $like,
                $digits
            ) {
                $builder
                    ->where('value', 'like', $like)
                    ->orWhere('label', 'like', $like)
                    ->orWhere('contact_person', 'like', $like)
                    ->orWhere('department', 'like', $like)
                    ->orWhere('type', 'like', $like);

                if (ctype_digit($search)) {
                    $builder->orWhere('id', (int) $search);
                }

                if ($digits !== '') {
                    $builder->orWhere(
                        'normalized_value',
                        'like',
                        '%' . $digits . '%'
                    );
                }
            });
        }

        return response()->json(
            $query
                ->orderByDesc('is_primary')
                ->orderBy('sort_order')
                ->orderBy('id')
                ->paginate(20)
        );
    }

    private function contactRules(bool $create): array
    {
        $prefix = $create ? 'required' : 'sometimes';

        return [
            'type' => [
                $prefix,
                Rule::in(['phone', 'email', 'whatsapp', 'other']),
            ],
            'value' => [
                $prefix, 'string', 'max:255',
            ],
            'label' => [
                'sometimes', 'nullable', 'string', 'max:100',
            ],
            'contact_person' => [
                'sometimes', 'nullable', 'string', 'max:180',
            ],
            'department' => [
                'sometimes', 'nullable', 'string', 'max:100',
            ],
            'is_primary' => ['sometimes', 'boolean'],
            'is_public' => ['sometimes', 'boolean'],
            'sort_order' => [
                'sometimes', 'integer', 'between:0,100000',
            ],
            'notes' => [
                'sometimes', 'nullable', 'string', 'max:2000',
            ],
        ];
    }

    private function normalizeContact(string $type, string $value): string
    {
        if (in_array($type, ['phone', 'whatsapp'], true)) {
            return preg_replace('/\D+/', '', $value);
        }

        return mb_strtolower(trim($value));
    }

    public function storeContact(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.contacts.manage'
        );

        $data = $request->validate($this->contactRules(true));

        $data['value'] = trim($data['value']);

        $data['normalized_value'] = $this->normalizeContact(
            $data['type'],
            $data['value']
        );

        $id = DB::table('company_contacts')->insertGetId(
            array_merge($data, [
                'company_id' => $company,
                'created_at' => now(),
                'updated_at' => now(),
            ])
        );

        return response()->json([
            'message' => 'Contacto creado.',
            'contact' => DB::table('company_contacts')
                ->where('company_id', $company)
                ->where('id', $id)
                ->first(),
        ], 201);
    }

    public function updateContact(
        Request $request,
        int $company,
        int $contact
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.contacts.manage'
        );

        $existing = DB::table('company_contacts')
            ->where('company_id', $company)
            ->where('id', $contact)
            ->first();

        if (!$existing) {
            abort(404, 'Contacto no encontrado.');
        }

        $data = $request->validate($this->contactRules(false));

        if (!$data) {
            return response()->json([
                'message' => 'No se recibieron cambios.',
            ], 422);
        }

        if (array_key_exists('value', $data)) {
            $data['value'] = trim($data['value']);
        }

        if (
            array_key_exists('value', $data)
            || array_key_exists('type', $data)
        ) {
            $data['normalized_value'] = $this->normalizeContact(
                $data['type'] ?? $existing->type,
                $data['value'] ?? $existing->value
            );
        }

        DB::table('company_contacts')
            ->where('company_id', $company)
            ->where('id', $contact)
            ->update(array_merge($data, [
                'updated_at' => now(),
            ]));

        return response()->json([
            'message' => 'Contacto actualizado.',
            'contact' => DB::table('company_contacts')
                ->where('company_id', $company)
                ->where('id', $contact)
                ->first(),
        ]);
    }

    public function deleteContact(
        Request $request,
        int $company,
        int $contact
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.contacts.manage'
        );

        $deleted = DB::table('company_contacts')
            ->where('company_id', $company)
            ->where('id', $contact)
            ->delete();

        if (!$deleted) {
            abort(404, 'Contacto no encontrado.');
        }

        return response()->json([
            'message' => 'Contacto eliminado.',
        ]);
    }
}