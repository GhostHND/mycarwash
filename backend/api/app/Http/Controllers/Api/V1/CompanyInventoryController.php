<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Bloque 18: categorias, proveedores, insumos y movimientos auditados. */
class CompanyInventoryController extends Controller
{
    private const TABLES = [
        'categories' => 'inventory_categories',
        'suppliers' => 'inventory_suppliers',
        'items' => 'inventory_items',
        'movements' => 'inventory_movements',
    ];

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
        if (!$allowed) abort(403, 'No autorizado.');
    }

    private function table(string $resource): string
    {
        return self::TABLES[$resource] ?? abort(404, 'Módulo inexistente.');
    }

    private function scoped(string $resource, int $company)
    {
        return DB::table($this->table($resource))->where('company_id', $company)->whereNull('deleted_at');
    }

    private function row(string $resource, int $company, int $id): object
    {
        return $this->scoped($resource, $company)->where('id', $id)->first() ?? abort(404, 'Registro no encontrado.');
    }

    private function relation(int $company, string $resource, ?int $id, string $field): void
    {
        if ($id !== null && !$this->scoped($resource, $company)
            ->where('id', $id)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages([$field => 'Selecciona un registro activo de tu empresa.']);
        }
    }

    private function branch(int $company, int $id): void
    {
        if (!DB::table('branches')->where('company_id', $company)->where('id', $id)
            ->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible para esta empresa.']);
        }
    }

    private function rules(string $resource, bool $create): array
    {
        $required = $create ? ['required'] : ['sometimes', 'required'];
        $optional = ['sometimes', 'nullable'];
        $flag = ['sometimes', 'boolean'];
        return match ($resource) {
            'categories' => [
                'name' => [...$required, 'string', 'max:140'],
                'description' => [...$optional, 'string', 'max:2000'],
                'is_active' => $flag,
            ],
            'suppliers' => [
                'name' => [...$required, 'string', 'max:160'],
                'tax_id' => [...$optional, 'string', 'max:40'],
                'phone' => [...$optional, 'string', 'max:50'],
                'email' => [...$optional, 'email', 'max:180'],
                'address' => [...$optional, 'string', 'max:500'],
                'notes' => [...$optional, 'string', 'max:2000'],
                'is_active' => $flag,
            ],
            'items' => [
                'sku' => [...$required, 'string', 'max:80'],
                'name' => [...$required, 'string', 'max:160'],
                'unit' => [...$required, Rule::in(['unidad','litro','ml','galon','kg','g','metro','paquete'])],
                'category_id' => [...$optional, 'integer', 'min:1'],
                'supplier_id' => [...$optional, 'integer', 'min:1'],
                'min_stock' => ['sometimes', 'numeric', 'min:0', 'max:99999999999'],
                'cost_price' => ['sometimes', 'numeric', 'min:0', 'max:99999999999'],
                'sale_price' => [...$optional, 'numeric', 'min:0', 'max:99999999999'],
                'description' => [...$optional, 'string', 'max:2000'],
                'is_active' => $flag,
            ],
            'movements' => [
                'branch_id' => [...$required, 'integer', 'min:1'],
                'item_id' => [...$required, 'integer', 'min:1'],
                'movement_type' => [...$required, Rule::in(['IN', 'OUT'])],
                'quantity' => [...$required, 'numeric', 'min:0.001', 'max:99999999999', 'regex:/^\d{1,11}(?:\.\d{1,3})?$/'],
                'reference' => [...$optional, 'string', 'max:100'],
                'notes' => [...$optional, 'string', 'max:2000'],
            ],
            default => abort(404, 'Módulo inexistente.'),
        };
    }

    private function validated(Request $request, int $company, string $resource, bool $create, ?object $previous = null): array
    {
        $data = $request->validate($this->rules($resource, $create));
        if ($resource === 'categories' || $resource === 'suppliers') {
            if (array_key_exists('name', $data)) {
                $data['name'] = trim($data['name']);
                if ($data['name'] === '') throw ValidationException::withMessages(['name' => 'El nombre es obligatorio.']);
                $exists = $this->scoped($resource, $company)->where('name', $data['name']);
                if ($previous) $exists->where('id', '!=', $previous->id);
                if ($exists->exists()) throw ValidationException::withMessages(['name' => 'El nombre ya existe en la empresa.']);
            }
        }
        if ($resource === 'items') {
            foreach (['category_id'=>'categories', 'supplier_id'=>'suppliers'] as $key => $rel) {
                if (array_key_exists($key, $data)) $this->relation($company, $rel, $data[$key], $key);
            }
            if (array_key_exists('name', $data) && trim($data['name']) === '') {
                throw ValidationException::withMessages(['name'=>'El nombre es obligatorio.']);
            }
            if (array_key_exists('sku', $data)) {
                $data['sku'] = strtoupper(trim($data['sku']));
                if ($data['sku'] === '') throw ValidationException::withMessages(['sku'=>'El SKU no puede estar vacío.']);
                $existing = $this->scoped('items', $company)->where('sku', $data['sku']);
                if ($previous) $existing->where('id', '!=', $previous->id);
                if ($existing->exists()) throw ValidationException::withMessages(['sku'=>'El SKU ya está registrado.']);
            }
            foreach (['min_stock'=>3, 'cost_price'=>2, 'sale_price'=>2] as $key=>$scale) {
                if (isset($data[$key]) && preg_match('/\.\d{'.($scale+1).',}$/', (string)$data[$key])) {
                    throw ValidationException::withMessages([$key => "Máximo $scale decimales."]);
                }
            }
        }
        if ($resource === 'movements') {
            if ($previous !== null) {
                foreach (['branch_id','item_id'] as $field) {
                    if (array_key_exists($field,$data) && (int)$data[$field] !== (int)$previous->{$field}) {
                        throw ValidationException::withMessages([$field=>'La sucursal y el producto son inmutables. Corrige el movimiento o crea otro.']);
                    }
                    unset($data[$field]);
                }
            } else {
                $this->branch($company, (int)$data['branch_id']);
                $this->relation($company, 'items', (int)$data['item_id'], 'item_id');
            }
        }
        return $data;
    }

    private function milli(string|int|float $number): int
    {
        $value = (string)$number;
        if (!preg_match('/^(\d+)(?:\.(\d{1,3}))?$/', $value, $match)) {
            throw ValidationException::withMessages(['quantity'=>'Cantidad inválida (máximo 3 decimales).']);
        }
        return (int)$match[1] * 1000 + (int)str_pad($match[2] ?? '', 3, '0');
    }

    private function balanceMilli(int $company, int $branch, int $item, ?int $exclude = null): int
    {
        $query = $this->scoped('movements', $company)->where('branch_id', $branch)->where('item_id', $item);
        if ($exclude !== null) $query->where('id', '!=', $exclude);
        $quantity = $query->selectRaw("COALESCE(SUM(CASE WHEN movement_type='IN' THEN quantity ELSE -quantity END), 0) AS balance")->first()->balance;
        $txt = (string)$quantity;
        if (str_starts_with($txt, '-')) return -$this->milli(substr($txt, 1));
        return $this->milli($txt);
    }

    private function movementStockGuard(int $company, int $branch, int $item, string $type, string|int|float $quantity,
        ?int $exclude = null): void
    {
        $net = $this->balanceMilli($company, $branch, $item, $exclude);
        $change = $this->milli($quantity) * ($type === 'IN' ? 1 : -1);
        if ($net + $change < 0) {
            throw ValidationException::withMessages(['quantity'=>'Existencia insuficiente: la corrección dejaría stock negativo.']);
        }
    }

    private function event(int $company, int $id, string $action, ?object $before, ?object $after, int $userId): void
    {
        DB::table('inventory_movement_events')->insert([
            'company_id'=>$company, 'movement_id'=>$id, 'action'=>$action,
            'before_json'=>$before ? json_encode($before, JSON_UNESCAPED_UNICODE) : null,
            'after_json'=>$after ? json_encode($after, JSON_UNESCAPED_UNICODE) : null,
            'actor_user_id'=>$userId, 'occurred_at'=>now(),
        ]);
    }

    private function decorate(string $resource, int $company, object $row): array
    {
        $result = (array)$row;
        if ($resource === 'items') {
            $result['category_name'] = $row->category_id ? $this->scoped('categories',$company)->where('id',$row->category_id)->value('name') : null;
            $result['supplier_name'] = $row->supplier_id ? $this->scoped('suppliers',$company)->where('id',$row->supplier_id)->value('name') : null;
            $total = $this->scoped('movements',$company)->where('item_id',$row->id)
                ->selectRaw("COALESCE(SUM(CASE WHEN movement_type='IN' THEN quantity ELSE -quantity END),0) AS balance")->first()->balance;
            $result['stock_total'] = $total;
        }
        if ($resource === 'movements') {
            $result['item_name'] = DB::table('inventory_items')->where('company_id',$company)
                ->where('id',$row->item_id)->value('name');
            $result['branch_name'] = DB::table('branches')->where('company_id',$company)
                ->where('id',$row->branch_id)->value('name');
        }
        return $result;
    }

    public function options(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        return response()->json(['data'=>[
            'branches'=>DB::table('branches')->where('company_id',$company)->where('is_active',true)->orderBy('name')->get(['id','name']),
            'categories'=>$this->scoped('categories',$company)->where('is_active',true)->orderBy('name')->get(['id','name']),
            'suppliers'=>$this->scoped('suppliers',$company)->where('is_active',true)->orderBy('name')->get(['id','name']),
            'items'=>$this->scoped('items',$company)->where('is_active',true)->orderBy('name')->get(['id','name','sku','unit']),
        ]]);
    }

    public function stock(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $v=$request->validate(['branch_id'=>['required','integer','min:1'], 'item_id'=>['required','integer','min:1']]);
        $this->branch($company,(int)$v['branch_id']);
        $this->row('items',$company,(int)$v['item_id']);
        return response()->json(['data'=>['branch_id'=>(int)$v['branch_id'],'item_id'=>(int)$v['item_id'],
            'quantity'=>number_format($this->balanceMilli($company,(int)$v['branch_id'],(int)$v['item_id'])/1000,3,'.','')]]);
    }

    public function history(Request $request,int $company,int $movement): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $exists=DB::table('inventory_movements')->where('company_id',$company)->where('id',$movement)->exists();
        if (!$exists) abort(404,'Movimiento no encontrado.');
        return response()->json(['data'=>DB::table('inventory_movement_events')->where('company_id',$company)
            ->where('movement_id',$movement)->orderBy('id')->get()]);
    }

    public function index(Request $request,int $company,string $resource): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $this->table($resource);
        $v=$request->validate(['q'=>['sometimes','nullable','string','max:150'],
            'page'=>['sometimes','integer','min:1'],'per_page'=>['sometimes','integer','between:1,50']]);
        $query=$this->scoped($resource,$company);
        if (!empty($v['q'])) {
            $search = trim($v['q']);
            $fields = match($resource) {
                'categories'=>['name','description'],
                'suppliers'=>['name','tax_id','phone','email'],
                'items'=>['sku','name','unit'],
                'movements'=>['reference','notes'],
            };
            $query->where(function($builder)use($search,$fields):void {
                foreach($fields as $field) $builder->orWhere($field,'like','%'.$search.'%');
            });
        }
        $list=$query->orderByDesc('id')->paginate($v['per_page'] ?? 10)->toArray();
        $list['data']=array_map(fn($record)=>$this->decorate($resource,$company,(object)$record),$list['data']);
        return response()->json($list);
    }

    public function show(Request $request,int $company,string $resource,int $record): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        return response()->json(['data'=>$this->decorate($resource,$company,$this->row($resource,$company,$record))]);
    }

    public function store(Request $request,int $company,string $resource): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update');
        $this->table($resource);
        $data=$this->validated($request,$company,$resource,true);
        $result=DB::transaction(function()use($request,$company,$resource,$data):object {
            if ($resource === 'movements') {
                $locked=$this->scoped('items',$company)->where('id',$data['item_id'])->where('is_active',true)->lockForUpdate()->first();
                if (!$locked) throw ValidationException::withMessages(['item_id'=>'Producto no disponible.']);
                $this->branch($company,(int)$data['branch_id']);
                $this->movementStockGuard($company,(int)$data['branch_id'],(int)$data['item_id'],
                    $data['movement_type'],(string)$data['quantity']);
                $data['actor_user_id']=$request->user()->id;
            }
            $id=DB::table($this->table($resource))->insertGetId([...$data,'company_id'=>$company,
                'created_at'=>now(),'updated_at'=>now()]);
            $row=$this->row($resource,$company,$id);
            if ($resource==='movements') $this->event($company,$id,'CREATE',null,$row,$request->user()->id);
            return $row;
        });
        return response()->json(['data'=>$this->decorate($resource,$company,$result)],201);
    }

    private function assertNoLinkedItems(string $resource,int $company,int $id): void
    {
        $key=$resource==='categories'?'category_id':'supplier_id';
        if ($this->scoped('items',$company)->where($key,$id)->exists()) {
            throw ValidationException::withMessages(['id'=>'Existen productos relacionados. Reasígnalos o archívalos primero.']);
        }
    }

    private function assertItemCanArchive(int $company,int $id): void
    {
        // Impedir ocultar un producto que tenga existencias en cualquier sucursal.
        $branches=$this->scoped('movements',$company)->where('item_id',$id)->distinct()->pluck('branch_id');
        foreach ($branches as $branch) {
            if ($this->balanceMilli($company,(int)$branch,$id) !== 0) {
                throw ValidationException::withMessages(['id'=>'El producto aún tiene existencias; regulariza el saldo antes de archivarlo.']);
            }
        }
    }

    public function update(Request $request,int $company,string $resource,int $record): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update');
        $this->table($resource);
        $result=DB::transaction(function() use($request,$company,$resource,$record):object {
            $existing=$this->row($resource,$company,$record);
            if ($resource==='movements') {
                $locked=$this->scoped('items',$company)->where('id',$existing->item_id)->lockForUpdate()->first();
                if (!$locked) abort(409,'Producto no disponible.');
                $existing=$this->row($resource,$company,$record);
            }
            $data=$this->validated($request,$company,$resource,false,$existing);
            if (array_key_exists('is_active',$data) && !$data['is_active']) {
                if (in_array($resource,['categories','suppliers'],true)) $this->assertNoLinkedItems($resource,$company,$record);
                if ($resource==='items') $this->assertItemCanArchive($company,$record);
            }
            if ($resource==='movements') {
                $type=$data['movement_type'] ?? $existing->movement_type;
                $quantity=$data['quantity'] ?? $existing->quantity;
                $this->movementStockGuard($company,(int)$existing->branch_id,(int)$existing->item_id,
                    $type,(string)$quantity,$record);
            }
            if (!$data) return $existing;
            DB::table($this->table($resource))->where('id',$record)->where('company_id',$company)
                ->update([...$data,'updated_at'=>now()]);
            $updated=$this->row($resource,$company,$record);
            if ($resource==='movements') $this->event($company,$record,'UPDATE',$existing,$updated,$request->user()->id);
            return $updated;
        });
        return response()->json(['data'=>$this->decorate($resource,$company,$result)]);
    }

    public function destroy(Request $request,int $company,string $resource,int $record): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update');
        $this->table($resource);
        DB::transaction(function()use($request,$company,$resource,$record):void {
            $existing=$this->row($resource,$company,$record);
            if (in_array($resource,['categories','suppliers'],true)) $this->assertNoLinkedItems($resource,$company,$record);
            if ($resource==='items') $this->assertItemCanArchive($company,$record);
            if ($resource==='movements') {
                $lock=$this->scoped('items',$company)->where('id',$existing->item_id)->lockForUpdate()->first();
                if (!$lock) abort(409,'Producto no disponible.');
                $existing=$this->row($resource,$company,$record);
                // Eliminar un ingreso revierte su saldo; prohibido si causa stock negativo.
                $balance=$this->balanceMilli($company,(int)$existing->branch_id,(int)$existing->item_id,$record);
                if ($balance < 0) throw ValidationException::withMessages(['id'=>'No puedes eliminar el movimiento: dejaría stock negativo.']);
            }
            DB::table($this->table($resource))->where('id',$record)->where('company_id',$company)
                ->update(['deleted_at'=>now(),'updated_at'=>now()]);
            if ($resource==='movements') $this->event($company,$record,'DELETE',$existing,null,$request->user()->id);
        });
        return response()->json(['message'=>'Registro archivado correctamente.']);
    }
}
