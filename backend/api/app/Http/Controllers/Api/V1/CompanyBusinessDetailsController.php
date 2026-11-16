<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CompanyBusinessDetailsController extends Controller
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

        abort_unless(
            $allowed,
            403,
            'No tienes permiso para realizar esta operación.'
        );
    }

    // ====================================================
    // DATOS FISCALES
    // ====================================================

    private function fiscalRules(): array
    {
        return [
            'legal_name' => [
                'sometimes', 'nullable', 'string', 'max:180',
            ],
            'tax_id' => [
                'sometimes', 'nullable', 'string', 'max:60',
            ],
            'taxpayer_type' => [
                'sometimes', 'nullable', 'string', 'max:100',
            ],
            'tax_regime' => [
                'sometimes', 'nullable', 'string', 'max:120',
            ],
            'tax_status' => [
                'sometimes', 'nullable', 'string', 'max:100',
            ],
            'commercial_registration' => [
                'sometimes', 'nullable', 'string', 'max:120',
            ],
            'billing_email' => [
                'sometimes', 'nullable', 'email', 'max:190',
            ],
            'billing_phone' => [
                'sometimes', 'nullable', 'string', 'max:40',
            ],
            'fiscal_address' => [
                'sometimes', 'nullable', 'string', 'max:5000',
            ],
            'invoice_footer' => [
                'sometimes', 'nullable', 'string', 'max:5000',
            ],
            'fiscal_notes' => [
                'sometimes', 'nullable', 'string', 'max:5000',
            ],
            'is_tax_exempt' => [
                'sometimes', 'boolean',
            ],
        ];
    }

    public function fiscal(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.fiscal.manage'
        );

        return response()->json([
            'fiscal' => DB::table('company_fiscal_profiles')
                ->where('company_id', $company)
                ->first(),
        ]);
    }

    public function saveFiscal(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.fiscal.manage'
        );

        $data = $request->validate($this->fiscalRules());

        if (!$data) {
            return response()->json([
                'message' => 'No se recibieron campos fiscales.',
            ], 422);
        }

        DB::transaction(function () use ($company, $data) {
            // Serializa las escrituras de la misma empresa.
            DB::table('companies')
                ->where('id', $company)
                ->lockForUpdate()
                ->first(['id']);

            $exists = DB::table('company_fiscal_profiles')
                ->where('company_id', $company)
                ->exists();

            if ($exists) {
                DB::table('company_fiscal_profiles')
                    ->where('company_id', $company)
                    ->update(array_merge($data, [
                        'updated_at' => now(),
                    ]));
            } else {
                DB::table('company_fiscal_profiles')->insert(
                    array_merge($data, [
                        'company_id' => $company,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ])
                );
            }
        });

        return response()->json([
            'message' => 'Datos fiscales guardados.',
            'fiscal' => DB::table('company_fiscal_profiles')
                ->where('company_id', $company)
                ->first(),
        ]);
    }

    // ====================================================
    // DIRECCIONES
    // ====================================================

    private function addressRules(bool $create): array
    {
        return [
            'type' => [
                'sometimes', 'string', 'min:1', 'max:40',
            ],
            'country' => [
                'sometimes', 'string', 'min:1', 'max:100',
            ],
            'department' => [
                'sometimes', 'nullable', 'string', 'max:120',
            ],
            'municipality' => [
                'sometimes', 'nullable', 'string', 'max:120',
            ],
            'neighborhood' => [
                'sometimes', 'nullable', 'string', 'max:180',
            ],
            'street' => [
                'sometimes', 'nullable', 'string', 'max:255',
            ],
            'building_number' => [
                'sometimes', 'nullable', 'string', 'max:50',
            ],
            'postal_code' => [
                'sometimes', 'nullable', 'string', 'max:30',
            ],
            'full_address' => [
                'sometimes', 'nullable', 'string', 'max:5000',
            ],
            'reference' => [
                'sometimes', 'nullable', 'string', 'max:5000',
            ],
            'latitude' => [
                'sometimes', 'nullable', 'numeric', 'between:-90,90',
            ],
            'longitude' => [
                'sometimes', 'nullable', 'numeric', 'between:-180,180',
            ],
            'is_primary' => [
                'sometimes', 'boolean',
            ],
        ];
    }

    public function addresses(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.view'
        );

        $filters = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'per_page' => [
                'sometimes', 'integer', 'between:1,50',
            ],
        ]);

        $search = trim($filters['q'] ?? '');
        $perPage = (int) ($filters['per_page'] ?? 20);

        $query = DB::table('company_addresses')
            ->where('company_id', $company);

        if ($search !== '') {
            $like = '%' . $search . '%';

            $query->where(function ($builder) use ($search, $like) {
                foreach ([
                    'type',
                    'country',
                    'department',
                    'municipality',
                    'neighborhood',
                    'street',
                    'building_number',
                    'postal_code',
                    'full_address',
                    'reference',
                ] as $field) {
                    $builder->orWhere($field, 'like', $like);
                }

                if (ctype_digit($search)) {
                    $builder->orWhere('id', (int) $search);
                }
            });
        }

        return response()->json(
            $query
                ->orderByDesc('is_primary')
                ->orderBy('id')
                ->paginate($perPage)
        );
    }

    public function storeAddress(
        Request $request,
        int $company
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.update'
        );

        $data = $request->validate($this->addressRules(true));

        $hasLocation = false;

        foreach ([
            'full_address',
            'street',
            'neighborhood',
            'municipality',
        ] as $field) {
            if (trim((string) ($data[$field] ?? '')) !== '') {
                $hasLocation = true;
                break;
            }
        }

        if (!$hasLocation) {
            return response()->json([
                'message' => 'Indica al menos una ubicación o dirección.',
            ], 422);
        }

        $data['country'] = $data['country'] ?? 'Honduras';
        $data['type'] = $data['type'] ?? 'principal';

        $id = DB::transaction(function () use ($company, $data) {
            DB::table('companies')
                ->where('id', $company)
                ->lockForUpdate()
                ->first(['id']);

            $hasAddresses = DB::table('company_addresses')
                ->where('company_id', $company)
                ->exists();

            $primary = (bool) ($data['is_primary'] ?? false);

            // La primera dirección será principal.
            if (!$hasAddresses) {
                $primary = true;
            }

            if ($primary) {
                DB::table('company_addresses')
                    ->where('company_id', $company)
                    ->update([
                        'is_primary' => false,
                        'updated_at' => now(),
                    ]);
            }

            $newData = $data;
            $newData['is_primary'] = $primary;

            return DB::table('company_addresses')->insertGetId(
                array_merge($newData, [
                    'company_id' => $company,
                    'created_at' => now(),
                    'updated_at' => now(),
                ])
            );
        });

        return response()->json([
            'message' => 'Dirección registrada.',
            'address' => DB::table('company_addresses')
                ->where('company_id', $company)
                ->where('id', $id)
                ->first(),
        ], 201);
    }

    public function updateAddress(
        Request $request,
        int $company,
        int $address
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.update'
        );

        $data = $request->validate($this->addressRules(false));

        if (!$data) {
            return response()->json([
                'message' => 'No se recibieron cambios.',
            ], 422);
        }

        DB::transaction(function () use ($company, $address, $data) {
            DB::table('companies')
                ->where('id', $company)
                ->lockForUpdate()
                ->first(['id']);

            $existing = DB::table('company_addresses')
                ->where('company_id', $company)
                ->where('id', $address)
                ->first();

            abort_unless(
                $existing,
                404,
                'Dirección no encontrada.'
            );

            if (!empty($data['is_primary'])) {
                DB::table('company_addresses')
                    ->where('company_id', $company)
                    ->update([
                        'is_primary' => false,
                        'updated_at' => now(),
                    ]);
            }

            DB::table('company_addresses')
                ->where('company_id', $company)
                ->where('id', $address)
                ->update(array_merge($data, [
                    'updated_at' => now(),
                ]));
        });

        return response()->json([
            'message' => 'Dirección actualizada.',
            'address' => DB::table('company_addresses')
                ->where('company_id', $company)
                ->where('id', $address)
                ->first(),
        ]);
    }

    public function deleteAddress(
        Request $request,
        int $company,
        int $address
    ): JsonResponse {
        $this->authorizeCompany(
            $request,
            $company,
            'company.update'
        );

        DB::transaction(function () use ($company, $address) {
            DB::table('companies')
                ->where('id', $company)
                ->lockForUpdate()
                ->first(['id']);

            $existing = DB::table('company_addresses')
                ->where('company_id', $company)
                ->where('id', $address)
                ->first();

            abort_unless(
                $existing,
                404,
                'Dirección no encontrada.'
            );

            DB::table('company_addresses')
                ->where('company_id', $company)
                ->where('id', $address)
                ->delete();

            // Si se elimina la principal, promocionar otra.
            if ($existing->is_primary) {
                $next = DB::table('company_addresses')
                    ->where('company_id', $company)
                    ->orderBy('id')
                    ->first(['id']);

                if ($next) {
                    DB::table('company_addresses')
                        ->where('company_id', $company)
                        ->where('id', $next->id)
                        ->update([
                            'is_primary' => true,
                            'updated_at' => now(),
                        ]);
                }
            }
        });

        return response()->json([
            'message' => 'Dirección eliminada.',
        ]);
    }
}