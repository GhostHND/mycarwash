<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Bloque 19: caja manual por sucursal; sin cobros automaticos ni documentos fiscales. */
class CompanyCashController extends Controller
{
    private const TABLES = [
        'registers' => 'cash_registers',
        'sessions' => 'cash_sessions',
        'categories' => 'cash_expense_categories',
        'movements' => 'cash_movements',
    ];

    private function check(Request $request, int $company, string $permission): void
    {
        $user = $request->user();
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $user->id)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $user->id)
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

    private function record(string $resource, int $company, int $id): object
    {
        return $this->scoped($resource, $company)->where('id', $id)->first()
            ?? abort(404, 'Registro no encontrado.');
    }

    private function branch(int $company, int $id): void
    {
        if (!DB::table('branches')->where('company_id', $company)->where('id', $id)
            ->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal ajena o inactiva.']);
        }
    }

    private function active(int $company, string $resource, int $id, string $field): object
    {
        $r = $this->scoped($resource, $company)->where('id', $id)->where('is_active', true)->first();
        if (!$r) throw ValidationException::withMessages([$field => 'Selecciona un registro activo de tu empresa.']);
        return $r;
    }

    private function rules(string $resource, bool $create): array
    {
        $required = $create ? ['required'] : ['sometimes', 'required'];
        $optional = ['sometimes', 'nullable'];
        $amount = ['regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?$/'];
        return match ($resource) {
            'registers' => [
                'branch_id' => [...$required, 'integer', 'min:1'],
                'code' => [...$required, 'string', 'max:40'],
                'name' => [...$required, 'string', 'max:140'],
                'notes' => [...$optional, 'string', 'max:2000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'categories' => [
                'name' => [...$required, 'string', 'max:140'],
                'description' => [...$optional, 'string', 'max:2000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'sessions' => [
                'register_id' => [...$required, 'integer', 'min:1'],
                'opening_cash' => [...$required, ...$amount],
                'notes' => [...$optional, 'string', 'max:2000'],
                'status' => ['sometimes', Rule::in(['OPEN', 'CLOSED'])],
                'counted_cash' => [...$optional, ...$amount],
            ],
            'movements' => [
                'session_id' => [...$required, 'integer', 'min:1'],
                'direction' => [...$required, Rule::in(['IN', 'OUT'])],
                'amount' => [...$required, ...$amount],
                'expense_category_id' => [...$optional, 'integer', 'min:1'],
                'reference' => [...$optional, 'string', 'max:100'],
                'notes' => [...$optional, 'string', 'max:2000'],
            ],
            default => abort(404, 'Módulo inexistente.'),
        };
    }

    private function money(string|int|float $amount, string $field = 'amount'): int
    {
        $str = (string)$amount;
        if (!preg_match('/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?$/', $str)) {
            throw ValidationException::withMessages([$field => 'Monto inválido: máximo dos decimales.']);
        }
        $parts = explode('.', $str, 2);
        return ((int)$parts[0] * 100) + (int)str_pad($parts[1] ?? '', 2, '0');
    }

    private function formatted(int $cents): string
    {
        $negative = $cents < 0 ? '-' : '';
        $abs = abs($cents);
        return $negative.intdiv($abs, 100).'.'.str_pad((string)($abs % 100), 2, '0', STR_PAD_LEFT);
    }

    /** Uniforma DECIMAL(14,2) de MySQL y SQLite sin convertir importes a float. */
    private function storedMoney(mixed $raw): ?string
    {
        if ($raw === null) return null;
        $value = (string) $raw;
        if (!preg_match('/^(-?)([0-9]+)(?:\.([0-9]{1,2}))?$/D', $value, $parts)) {
            throw new \UnexpectedValueException('El importe almacenado tiene un formato inesperado.');
        }
        $units = ltrim($parts[2], '0');
        if ($units === '') $units = '0';
        $decimals = str_pad($parts[3] ?? '', 2, '0');
        $sign = $parts[1] === '-' && ($units !== '0' || $decimals !== '00') ? '-' : '';
        return $sign.$units.'.'.$decimals;
    }

    private function expected(int $company, object $session, ?int $excluded = null,
        ?array $substitute = null): int
    {
        $balance = $this->money($session->opening_cash, 'opening_cash');
        $rows = $this->scoped('movements', $company)->where('session_id', $session->id)
            ->orderBy('id')->get(['id','direction','amount']);
        $found = false;
        foreach ($rows as $row) {
            if ($excluded !== null && (int)$row->id === $excluded) {
                $found = true;
                if ($substitute === null) continue;
                $row = (object)$substitute;
            }
            $balance += $this->money($row->amount) * ($row->direction === 'IN' ? 1 : -1);
            if ($balance < 0) {
                throw ValidationException::withMessages(['amount'=>'La operación dejaría efectivo negativo en el historial de la sesión.']);
            }
        }
        if ($substitute !== null && !$found) {
            $balance += $this->money($substitute['amount']) * ($substitute['direction'] === 'IN' ? 1 : -1);
            if ($balance < 0) {
                throw ValidationException::withMessages(['amount'=>'El egreso supera el efectivo disponible.']);
            }
        }
        return $balance;
    }

    private function lockSession(int $company, int $id): object
    {
        // Toda operación monetaria serializa primero la misma caja, incluso si distintas sesiones existen.
        $session = $this->record('sessions', $company, $id);
        $register = $this->scoped('registers', $company)->where('id', $session->register_id)
            ->lockForUpdate()->first();
        if (!$register) abort(409, 'Caja no disponible.');
        return $this->scoped('sessions', $company)->where('id', $id)->lockForUpdate()->first()
            ?? abort(404, 'Sesión no disponible.');
    }

    private function openSession(int $company, int $id): object
    {
        $session = $this->lockSession($company, $id);
        if ($session->status !== 'OPEN') {
            throw ValidationException::withMessages(['session_id'=>'La sesión está cerrada. No se puede modificar su efectivo.']);
        }
        return $session;
    }

    private function validatedMovement(array $data, int $company, ?object $old = null): array
    {
        $direction = $data['direction'] ?? ($old?->direction);
        $amount = $data['amount'] ?? ($old?->amount);
        if ($this->money($amount) <= 0) {
            throw ValidationException::withMessages(['amount' => 'El monto debe ser mayor a cero.']);
        }
        $category = array_key_exists('expense_category_id', $data)
            ? $data['expense_category_id'] : ($old?->expense_category_id);
        if ($direction === 'OUT') {
            if ($category === null) {
                throw ValidationException::withMessages(['expense_category_id'=>'Selecciona el concepto del egreso.']);
            }
            // Conservar categoria histórica si no se cambia, aunque luego se desactive.
            if ($old === null || array_key_exists('expense_category_id', $data)) {
                $this->active($company, 'categories', (int)$category, 'expense_category_id');
            }
        } else {
            $data['expense_category_id'] = null;
        }
        return $data;
    }

    private function event(int $company, int $id, string $action, ?object $before, ?object $after, int $actor): void
    {
        DB::table('cash_movement_events')->insert([
            'company_id' => $company, 'movement_id' => $id, 'action' => $action,
            'before_json' => $before ? json_encode($before, JSON_UNESCAPED_UNICODE) : null,
            'after_json' => $after ? json_encode($after, JSON_UNESCAPED_UNICODE) : null,
            'actor_user_id' => $actor, 'occurred_at' => now(),
        ]);
    }

    private function decorated(int $company, string $resource, object $row): array
    {
        $data = (array)$row;
        if ($resource === 'registers') {
            $data['branch_name'] = DB::table('branches')->where('company_id',$company)
                ->where('id',$row->branch_id)->value('name');
        }
        if ($resource === 'sessions') {
            foreach (['opening_cash', 'counted_cash', 'expected_cash', 'difference_cash'] as $field) {
                $data[$field] = $this->storedMoney($row->{$field});
            }
            $data['register_name'] = DB::table('cash_registers')->where('company_id',$company)
                ->where('id',$row->register_id)->value('name');
            $data['expected_current'] = $this->formatted($this->expected($company,$row));
        }
        if ($resource === 'movements') {
            $data['amount'] = $this->storedMoney($row->amount);
            $data['register_name'] = DB::table('cash_sessions as s')->join('cash_registers as r','r.id','=','s.register_id')
                ->where('s.company_id',$company)->where('s.id',$row->session_id)->value('r.name');
            $data['expense_name'] = $row->expense_category_id === null ? null :
                DB::table('cash_expense_categories')->where('company_id',$company)
                    ->where('id',$row->expense_category_id)->value('name');
        }
        return $data;
    }

    public function options(Request $request, int $company): JsonResponse
    {
        $this->check($request,$company,'company.view');
        return response()->json(['data' => [
            'branches' => DB::table('branches')->where('company_id',$company)
                ->where('is_active',true)->orderBy('name')->get(['id','name']),
            'registers' => $this->scoped('registers',$company)->where('is_active',true)
                ->orderBy('name')->get(['id','name','branch_id','currency']),
            'categories' => $this->scoped('categories',$company)->where('is_active',true)
                ->orderBy('name')->get(['id','name']),
            'sessions' => $this->scoped('sessions',$company)->where('status','OPEN')
                ->orderByDesc('id')->get(['id','register_id','opening_cash'])
                ->map(fn ($session) => [
                    'id' => $session->id,
                    'register_id' => $session->register_id,
                    'opening_cash' => $this->storedMoney($session->opening_cash),
                ]),
        ]]);
    }

    public function history(Request $request, int $company, int $movement): JsonResponse
    {
        $this->check($request,$company,'company.view');
        if (!DB::table('cash_movements')->where('company_id',$company)->where('id',$movement)->exists()) {
            abort(404,'Movimiento no encontrado.');
        }
        return response()->json(['data'=>DB::table('cash_movement_events')->where('company_id',$company)
            ->where('movement_id',$movement)->orderBy('id')->get()]);
    }

    public function index(Request $request, int $company, string $resource): JsonResponse
    {
        $this->check($request,$company,'company.view');
        $this->table($resource);
        $data = $request->validate(['q'=>['sometimes','nullable','string','max:150'],
            'page'=>['sometimes','integer','min:1'], 'per_page'=>['sometimes','integer','between:1,50']]);
        $query = $this->scoped($resource,$company);
        if (!empty($data['q'])) {
            $terms = match($resource) {
                'registers'=>['code','name','notes'], 'categories'=>['name','description'],
                'sessions'=>['notes','status'], 'movements'=>['reference','notes'],
            };
            $query->where(function($q) use ($terms,$data): void {
                foreach($terms as $term) $q->orWhere($term,'like','%'.trim($data['q']).'%');
            });
        }
        $list = $query->orderByDesc('id')->paginate($data['per_page'] ?? 10)->toArray();
        $list['data'] = array_map(fn($r)=>$this->decorated($company,$resource,(object)$r), $list['data']);
        return response()->json($list);
    }

    public function show(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->check($request,$company,'company.view');
        return response()->json(['data'=>$this->decorated($company,$resource,$this->record($resource,$company,$record))]);
    }

    public function store(Request $request, int $company, string $resource): JsonResponse
    {
        $this->check($request,$company,'company.update');
        $this->table($resource);
        $data=$request->validate($this->rules($resource,true));
        $row=DB::transaction(function() use ($request,$company,$resource,$data):object {
            if ($resource === 'registers') {
                $this->branch($company,(int)$data['branch_id']);
                $data['code']=strtoupper(trim($data['code'])); $data['name']=trim($data['name']);
                if ($data['code']==='' || $data['name']==='') throw ValidationException::withMessages(['code'=>'Código y nombre obligatorios.']);
                if ($this->scoped('registers',$company)->where('branch_id',$data['branch_id'])->where('code',$data['code'])->exists()) {
                    throw ValidationException::withMessages(['code'=>'Código de caja repetido en esta sucursal.']);
                }
                $data['currency']='HNL';
            }
            if ($resource === 'categories') {
                $data['name']=trim($data['name']);
                if ($data['name']==='') throw ValidationException::withMessages(['name'=>'Nombre obligatorio.']);
                if ($this->scoped('categories',$company)->where('name',$data['name'])->exists())
                    throw ValidationException::withMessages(['name'=>'Categoría duplicada.']);
            }
            if ($resource === 'sessions') {
                if (array_key_exists('status',$data) && $data['status'] !== 'OPEN')
                    throw ValidationException::withMessages(['status'=>'Una sesión nueva inicia abierta.']);
                if (array_key_exists('counted_cash',$data) && $data['counted_cash'] !== null)
                    throw ValidationException::withMessages(['counted_cash'=>'El conteo se registra al cierre.']);
                unset($data['status'], $data['counted_cash']);
                $reg=$this->scoped('registers',$company)->where('id',$data['register_id'])->lockForUpdate()->first();
                if (!$reg || !$reg->is_active) throw ValidationException::withMessages(['register_id'=>'Caja inactiva o ajena.']);
                if ($this->scoped('sessions',$company)->where('register_id',$reg->id)->where('status','OPEN')->exists()) {
                    throw ValidationException::withMessages(['register_id'=>'Esta caja ya tiene una sesión abierta.']);
                }
                $this->money($data['opening_cash'],'opening_cash');
                $data += ['status'=>'OPEN','open_register_id'=>$reg->id,'opened_by'=>$request->user()->id,'opened_at'=>now()];
            }
            if ($resource === 'movements') {
                if (!$this->scoped('sessions', $company)->where('id', (int) $data['session_id'])->exists()) {
                    throw ValidationException::withMessages([
                        'session_id' => 'La sesión indicada no existe o pertenece a otra empresa.',
                    ]);
                }
                $session=$this->openSession($company,(int)$data['session_id']);
                $data=$this->validatedMovement($data,$company);
                $balance=$this->expected($company,$session,null,$data);
                if ($balance<0) throw ValidationException::withMessages(['amount'=>'El egreso supera el efectivo disponible.']);
                $data['actor_user_id']=$request->user()->id;
            }
            $id=DB::table($this->table($resource))->insertGetId([...$data,'company_id'=>$company,
                'created_at'=>now(),'updated_at'=>now()]);
            $result=$this->record($resource,$company,$id);
            if ($resource==='movements') $this->event($company,$id,'CREATE',null,$result,$request->user()->id);
            return $result;
        });
        return response()->json(['data'=>$this->decorated($company,$resource,$row)],201);
    }

    public function update(Request $request,int $company,string $resource,int $record): JsonResponse
    {
        $this->check($request,$company,'company.update');
        $this->table($resource);
        $data=$request->validate($this->rules($resource,false));
        $updated=DB::transaction(function()use($request,$company,$resource,$record,$data):object {
            $old=$this->record($resource,$company,$record);
            if ($resource==='registers') {
                $newBranch=$data['branch_id'] ?? $old->branch_id;
                if (isset($data['branch_id'])) $this->branch($company,(int)$newBranch);
                if (array_key_exists('code',$data)) $data['code']=strtoupper(trim($data['code']));
                if (array_key_exists('name',$data)) $data['name']=trim($data['name']);
                if (($data['code'] ?? $old->code)==='' || ($data['name'] ?? $old->name)==='')
                    throw ValidationException::withMessages(['name'=>'Código y nombre obligatorios.']);
                if ($this->scoped('registers',$company)->where('branch_id',$newBranch)
                    ->where('code',$data['code'] ?? $old->code)->where('id','!=',$record)->exists())
                    throw ValidationException::withMessages(['code'=>'Código de caja repetido.']);
                $linked=DB::table('cash_sessions')->where('company_id',$company)->where('register_id',$record)->exists();
                if ($linked && (int)$newBranch !== (int)$old->branch_id)
                    throw ValidationException::withMessages(['branch_id'=>'No puedes mover una caja con historial a otra sucursal.']);
                if ($linked && array_key_exists('is_active',$data) && !$data['is_active'] &&
                    $this->scoped('sessions',$company)->where('register_id',$record)->where('status','OPEN')->exists())
                    throw ValidationException::withMessages(['is_active'=>'Cierra primero las sesiones activas.']);
            }
            if ($resource==='categories') {
                if (array_key_exists('name',$data)) {
                    $data['name']=trim($data['name']);
                    if ($data['name']==='') throw ValidationException::withMessages(['name'=>'Nombre obligatorio.']);
                    if ($this->scoped('categories',$company)->where('name',$data['name'])->where('id','!=',$record)->exists())
                        throw ValidationException::withMessages(['name'=>'Categoría duplicada.']);
                }
                if (array_key_exists('is_active',$data) && !$data['is_active'] &&
                    $this->scoped('movements',$company)->where('expense_category_id',$record)->exists())
                    throw ValidationException::withMessages(['is_active'=>'Categoría en uso.']);
            }
            if ($resource==='sessions') {
                $old=$this->openSession($company,$record);
                if (isset($data['register_id']) && (int)$data['register_id']!==(int)$old->register_id)
                    throw ValidationException::withMessages(['register_id'=>'La caja de una sesión no se puede cambiar.']);
                unset($data['register_id']);
                $existingMoves=$this->scoped('movements',$company)->where('session_id',$record)->exists();
                if (isset($data['opening_cash']) && $existingMoves &&
                    $this->money($data['opening_cash'], 'opening_cash') !== $this->money($old->opening_cash, 'opening_cash')) {
                    throw ValidationException::withMessages(['opening_cash'=>'No se puede cambiar el fondo tras registrar movimientos.']);
                }
                if (isset($data['opening_cash'])) $this->money($data['opening_cash'],'opening_cash');
                $close=($data['status'] ?? 'OPEN')==='CLOSED';
                if ($close) {
                    if (isset($data['opening_cash']) &&
                        $this->money($data['opening_cash'], 'opening_cash') !== $this->money($old->opening_cash, 'opening_cash')) {
                        throw ValidationException::withMessages(['opening_cash'=>'Ajusta el fondo en una edición anterior al cierre.']);
                    }
                    if (!array_key_exists('counted_cash',$data) || $data['counted_cash']===null)
                        throw ValidationException::withMessages(['counted_cash'=>'Indica efectivo contado al cerrar.']);
                    $counted=$this->money($data['counted_cash'],'counted_cash');
                    $expected=$this->expected($company,$old);
                    if ($expected<0) throw ValidationException::withMessages(['opening_cash'=>'El saldo esperado es negativo.']);
                    $difference=$counted-$expected;
                    if ($difference!==0 && mb_strlen(trim((string)($data['notes'] ?? $old->notes ?? '')))<3)
                        throw ValidationException::withMessages(['notes'=>'Explica la diferencia de caja antes de cerrar.']);
                    $data += ['closed_at'=>now(),'closed_by'=>$request->user()->id];
                    $data['expected_cash']=$this->formatted($expected);
                    $data['difference_cash']=$this->formatted($difference);
                    $data['open_register_id']=null;
                } elseif (array_key_exists('counted_cash',$data) && $data['counted_cash']!==null) {
                    throw ValidationException::withMessages(['counted_cash'=>'El conteo se registra únicamente al cierre.']);
                }
            }
            if ($resource==='movements') {
                $session=$this->openSession($company,(int)$old->session_id);
                $old=$this->record('movements',$company,$record);
                if (isset($data['session_id']) && (int)$data['session_id']!==(int)$old->session_id)
                    throw ValidationException::withMessages(['session_id'=>'No se permite transferir un movimiento a otra sesión.']);
                unset($data['session_id']);
                $data=$this->validatedMovement($data,$company,$old);
                if ($this->expected($company,$session,$record,[
                    'direction'=>$data['direction'] ?? $old->direction,
                    'amount'=>$data['amount'] ?? $old->amount,
                ])<0) throw ValidationException::withMessages(['amount'=>'La corrección dejaría efectivo negativo.']);
            }
            if ($data) DB::table($this->table($resource))->where('id',$record)->where('company_id',$company)
                ->update([...$data,'updated_at'=>now()]);
            $result=$this->record($resource,$company,$record);
            if ($resource==='movements' && $data) $this->event($company,$record,'UPDATE',$old,$result,$request->user()->id);
            return $result;
        });
        return response()->json(['data'=>$this->decorated($company,$resource,$updated)]);
    }

    public function destroy(Request $request,int $company,string $resource,int $record): JsonResponse
    {
        $this->check($request,$company,'company.update');
        $this->table($resource);
        DB::transaction(function() use($request,$company,$resource,$record):void {
            $old=$this->record($resource,$company,$record);
            if ($resource==='registers' && DB::table('cash_sessions')->where('company_id',$company)
                ->where('register_id',$record)->exists())
                throw ValidationException::withMessages(['id'=>'Caja con sesiones históricas: desactívala, no la elimines.']);
            if ($resource==='categories' && DB::table('cash_movements')->where('company_id',$company)
                ->where('expense_category_id',$record)->exists())
                throw ValidationException::withMessages(['id'=>'Categoría con egresos históricos: desactívala.']);
            if ($resource==='sessions') {
                $old=$this->openSession($company,$record);
                if (DB::table('cash_movements')->where('company_id',$company)->where('session_id',$record)->exists())
                    throw ValidationException::withMessages(['id'=>'Sesión con movimientos: ciérrala, no la elimines.']);
                DB::table('cash_sessions')->where('company_id',$company)->where('id',$record)
                    ->update(['open_register_id'=>null]);
            }
            if ($resource==='movements') {
                $session=$this->openSession($company,(int)$old->session_id);
                $old=$this->record('movements',$company,$record);
                if ($this->expected($company,$session,$record)<0)
                    throw ValidationException::withMessages(['id'=>'Eliminar este movimiento dejaría efectivo negativo.']);
            }
            DB::table($this->table($resource))->where('company_id',$company)->where('id',$record)
                ->update(['deleted_at'=>now(),'updated_at'=>now()]);
            if ($resource==='movements') $this->event($company,$record,'DELETE',$old,null,$request->user()->id);
        });
        return response()->json(['message'=>'Registro archivado con éxito.']);
    }
}
