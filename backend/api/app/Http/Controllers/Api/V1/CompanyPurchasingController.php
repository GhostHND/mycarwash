<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Bloque 23A: compras y recepciones con inventario atómico e idempotencia. */
final class CompanyPurchasingController extends Controller
{
    private function access(Request $request, int $company, string $permission): void
    {
        $uid = (int) $request->user()->id;
        if (!DB::table('company_user')->join('companies','companies.id','=','company_user.company_id')
            ->where('company_user.company_id',$company)->where('company_user.user_id',$uid)
            ->where('company_user.status','active')->where('companies.is_active',true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $can = DB::table('user_roles as ur')->join('roles as r', function ($j): void {
            $j->on('r.id','=','ur.role_id')->on('r.company_id','=','ur.company_id');
        })->join('role_permission as rp','rp.role_id','=','r.id')
            ->join('permissions as p','p.id','=','rp.permission_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$uid)->where('p.code',$permission)->exists();
        if (!$can) abort(403,'Permiso insuficiente.');
    }

    private function branch(int $company, int $id): void
    {
        if (!DB::table('branches')->where('company_id',$company)->where('id',$id)->where('is_active',true)->exists()) {
            throw ValidationException::withMessages(['branch_id'=>'Sucursal inválida.']);
        }
    }

    private function active(int $company, string $table, int $id, string $field): object
    {
        $row=DB::table($table)->where('company_id',$company)->where('id',$id)
            ->where('is_active',true)->whereNull('deleted_at')->first();
        if (!$row) throw ValidationException::withMessages([$field=>'Registro no disponible en esta empresa.']);
        return $row;
    }

    private function qty(string|int|float $input): int
    {
        $s=(string)$input;
        if (!preg_match('/^([0-9]{1,11})(?:\.([0-9]{1,3}))?$/D',$s,$m)) {
            throw ValidationException::withMessages(['quantity'=>'Cantidad inválida. Máximo tres decimales.']);
        }
        return ((int)$m[1])*1000+(int)str_pad($m[2]??'',3,'0');
    }
    private function cents(string|int|float $input): int
    {
        $s=(string)$input;
        if (!preg_match('/^([0-9]{1,11})(?:\.([0-9]{1,2}))?$/D',$s,$m)) {
            throw ValidationException::withMessages(['unit_cost'=>'Costo inválido. Máximo dos decimales.']);
        }
        return ((int)$m[1])*100+(int)str_pad($m[2]??'',2,'0');
    }
    private function money(int $v): string { return intdiv($v,100).'.'.str_pad((string)($v%100),2,'0',STR_PAD_LEFT); }
    private function quantity(int $v): string { return intdiv($v,1000).'.'.str_pad((string)($v%1000),3,'0',STR_PAD_LEFT); }
    private function order(int $company, int $id, bool $lock=false): object
    {
        $q=DB::table('purchase_orders')->where('company_id',$company)->where('id',$id);
        if ($lock) $q->lockForUpdate();
        return $q->first() ?? abort(404, 'Orden de compra no encontrada.');
    }
    private function full(int $company, int $id): array
    {
        $order=$this->order($company,$id);
        // SQLite puede devolver DECIMAL como int/float; MySQL como string.
        // El contrato JSON conserva siempre dinero (2) y cantidades (3) en texto decimal.
        $order->total=$this->money($this->cents($order->total));
        $lines=DB::table('purchase_order_lines')->where('company_id',$company)->where('order_id',$id)->orderBy('id')->get();
        foreach ($lines as $line) {
            $line->ordered_quantity=$this->quantity($this->qty($line->ordered_quantity));
            $line->received_quantity=$this->quantity($this->qty($line->received_quantity));
            $line->unit_cost=$this->money($this->cents($line->unit_cost));
            $line->line_total=$this->money($this->cents($line->line_total));
        }
        $receipts=DB::table('purchase_receipts')->where('company_id',$company)->where('order_id',$id)
            ->orderByDesc('id')->get();
        return ['order'=>$order,'lines'=>$lines,'receipts'=>$receipts];
    }

    public function options(Request $request, int $company): JsonResponse
    {
        $this->access($request,$company,'company.view');
        return response()->json(['data'=>[
            'branches'=>DB::table('branches')->where('company_id',$company)->where('is_active',true)->orderBy('name')->get(['id','name']),
            'suppliers'=>DB::table('inventory_suppliers')->where('company_id',$company)->where('is_active',true)
                ->whereNull('deleted_at')->orderBy('name')->get(['id','name']),
            'items'=>DB::table('inventory_items')->where('company_id',$company)->where('is_active',true)
                ->whereNull('deleted_at')->orderBy('name')->get(['id','sku','name','unit','cost_price']),
        ]]);
    }

    public function index(Request $request, int $company): JsonResponse
    {
        $this->access($request,$company,'company.view');
        $v=$request->validate(['branch_id'=>['sometimes','integer','min:1'],
            'status'=>['sometimes','string','in:ORDERED,PARTIAL,RECEIVED,CANCELLED'],
            'page'=>['sometimes','integer','min:1']]);
        $q=DB::table('purchase_orders')->where('company_id',$company);
        if(isset($v['branch_id'])) { $this->branch($company,(int)$v['branch_id']); $q->where('branch_id',$v['branch_id']); }
        if(isset($v['status'])) $q->where('status',$v['status']);
        $page=$q->orderByDesc('id')->paginate(30);
        $page->getCollection()->transform(function (object $order): object {
            $order->total=$this->money($this->cents($order->total));
            return $order;
        });
        return response()->json($page);
    }
    public function show(Request $request, int $company, int $order): JsonResponse
    {
        $this->access($request,$company,'company.view');
        return response()->json(['data'=>$this->full($company,$order)]);
    }

    /** La orden crea únicamente un compromiso operativo; no mueve stock ni caja. */
    public function store(Request $request, int $company): JsonResponse
    {
        $this->access($request,$company,'company.update');
        $v=$request->validate([
            'branch_id'=>['required','integer','min:1'],
            'supplier_id'=>['required','integer','min:1'],
            'supplier_reference'=>['sometimes','nullable','string','max:100'],
            'notes'=>['sometimes','nullable','string','max:2000'],
            'lines'=>['required','array','min:1','max:40'],
            'lines.*.item_id'=>['required','integer','min:1','distinct'],
            'lines.*.quantity'=>['required','regex:/^\d{1,11}(?:\.\d{1,3})?$/'],
            'lines.*.unit_cost'=>['required','regex:/^\d{1,11}(?:\.\d{1,2})?$/'],
        ]);
        $this->branch($company,(int)$v['branch_id']);
        $this->active($company,'inventory_suppliers',(int)$v['supplier_id'],'supplier_id');
        $prepared=[]; $total=0;
        foreach($v['lines'] as $line) {
            $item=$this->active($company,'inventory_items',(int)$line['item_id'],'lines.item_id');
            $m=$this->qty($line['quantity']); $c=$this->cents($line['unit_cost']);
            if($m<=0) throw ValidationException::withMessages(['lines'=>'Cantidad debe ser mayor que cero.']);
            // Mitigar overflow y evitar cálculos flotantes.
            if ($m>1000000000 || $c>100000000) throw ValidationException::withMessages(['lines'=>'Cantidad/costo fuera de límite.']);
            $lineCents=intdiv($m*$c+500,1000);
            $total+=$lineCents;
            if($total>99999999999999) throw ValidationException::withMessages(['lines'=>'Total fuera de límite.']);
            $prepared[]=['item_id'=>$item->id,'sku_snapshot'=>$item->sku,
                'name_snapshot'=>$item->name,'unit_snapshot'=>$item->unit,
                'ordered_quantity'=>$this->quantity($m),'received_quantity'=>'0.000',
                'unit_cost'=>$this->money($c),'line_total'=>$this->money($lineCents)];
        }
        $now=now();
        $id=DB::transaction(function () use($company,$request,$v,$prepared,$total,$now): int {
            $id=DB::table('purchase_orders')->insertGetId([
                'company_id'=>$company,'branch_id'=>$v['branch_id'],'supplier_id'=>$v['supplier_id'],
                'number'=>'PENDIENTE-'.bin2hex(random_bytes(10)),'status'=>'ORDERED',
                'total'=>$this->money($total),'supplier_reference'=>$v['supplier_reference']??null,
                'notes'=>$v['notes']??null,'created_by'=>$request->user()->id,
                'created_at'=>$now,'updated_at'=>$now,
            ]);
            // Número legible después de obtener el identificador global.
            DB::table('purchase_orders')->where('id',$id)->update(['number'=>'OC-'.str_pad((string)$id,7,'0',STR_PAD_LEFT)]);
            foreach($prepared as $line) DB::table('purchase_order_lines')->insert([
                ...$line,'company_id'=>$company,'order_id'=>$id,'created_at'=>$now,'updated_at'=>$now,
            ]);
            return $id;
        }, 3);
        return response()->json(['data'=>$this->full($company,$id)],201);
    }

    /** Publicación atómica: no aumenta existencia hasta la recepción efectiva. */
    public function receive(Request $request, int $company, int $order): JsonResponse
    {
        $this->access($request,$company,'company.update');
        $v=$request->validate([
            'idempotency_key'=>['required','string','regex:/^[A-Za-z0-9_-]{12,80}$/'],
            'supplier_document'=>['sometimes','nullable','string','max:100'],
            'lines'=>['required','array','min:1','max:40'],
            'lines.*.order_line_id'=>['required','integer','min:1','distinct'],
            'lines.*.quantity'=>['required','regex:/^\d{1,11}(?:\.\d{1,3})?$/'],
        ]);
        $receiptId=DB::transaction(function() use ($request,$company,$order,$v): int {
            // Bloquear primero la orden: reintentos concurrentes se serializan aquí.
            $header=$this->order($company,$order,true);
            $exists=DB::table('purchase_receipts')->where('company_id',$company)
                ->where('idempotency_key',$v['idempotency_key'])->first();
            if ($exists) {
                if ((int)$exists->order_id !== $order) abort(409,'Clave reutilizada en otra orden.');
                return (int)$exists->id;
            }
            if (!in_array($header->status,['ORDERED','PARTIAL'],true)) abort(409,'La orden no acepta recepciones.');
            $this->branch($company,(int)$header->branch_id);
            $now=now();
            $id=DB::table('purchase_receipts')->insertGetId([
                'company_id'=>$company,'order_id'=>$order,'branch_id'=>$header->branch_id,
                'idempotency_key'=>$v['idempotency_key'],'supplier_document'=>$v['supplier_document']??null,
                'received_by'=>$request->user()->id,'received_at'=>$now,
                'created_at'=>$now,'updated_at'=>$now,
            ]);
            foreach ($v['lines'] as $line) {
                $q=DB::table('purchase_order_lines')->where('company_id',$company)
                    ->where('order_id',$order)->where('id',$line['order_line_id'])->lockForUpdate();
                $item=$q->first();
                if (!$item) throw ValidationException::withMessages(['lines'=>'Artículo fuera de la orden.']);
                $incoming=$this->qty($line['quantity']);
                $ordered=$this->qty($item->ordered_quantity);
                $already=$this->qty($item->received_quantity);
                if ($incoming<=0 || $incoming>($ordered-$already)) {
                    throw ValidationException::withMessages(['lines'=>'La recepción excede la cantidad pendiente.']);
                }
                $stock=DB::table('inventory_items')->where('company_id',$company)
                    ->where('id',$item->item_id)->where('is_active',true)->whereNull('deleted_at')
                    ->lockForUpdate()->first();
                if (!$stock) throw ValidationException::withMessages(['lines'=>'El producto del inventario ya no está activo.']);
                $mv=DB::table('inventory_movements')->insertGetId([
                    'company_id'=>$company,'branch_id'=>$header->branch_id,'item_id'=>$item->item_id,
                    'movement_type'=>'IN','quantity'=>$this->quantity($incoming),
                    'reference'=>'OC-'.str_pad((string)$order,7,'0',STR_PAD_LEFT),
                    'notes'=>'Recepción de compra #'.$id,'actor_user_id'=>$request->user()->id,
                    'created_at'=>$now,'updated_at'=>$now,
                ]);
                $after=DB::table('inventory_movements')->where('id',$mv)->first();
                DB::table('inventory_movement_events')->insert([
                    'company_id'=>$company,'movement_id'=>$mv,'action'=>'CREATE',
                    'before_json'=>null,'after_json'=>json_encode($after,JSON_UNESCAPED_UNICODE),
                    'actor_user_id'=>$request->user()->id,'occurred_at'=>$now,
                ]);
                DB::table('purchase_order_lines')->where('id',$item->id)->where('company_id',$company)
                    ->update(['received_quantity'=>$this->quantity($already+$incoming),'updated_at'=>$now]);
                DB::table('purchase_receipt_lines')->insert([
                    'company_id'=>$company,'receipt_id'=>$id,'order_line_id'=>$item->id,
                    'item_id'=>$item->item_id,'inventory_movement_id'=>$mv,
                    'quantity'=>$this->quantity($incoming),'unit_cost'=>$item->unit_cost,
                    'created_at'=>$now,'updated_at'=>$now,
                ]);
            }
            $pending=DB::table('purchase_order_lines')->where('company_id',$company)->where('order_id',$order)
                ->whereColumn('received_quantity','<','ordered_quantity')->exists();
            DB::table('purchase_orders')->where('company_id',$company)->where('id',$order)
                ->update(['status'=>$pending?'PARTIAL':'RECEIVED','updated_at'=>$now]);
            return $id;
        },3);
        return response()->json(['data'=>[
            'receipt_id'=>$receiptId,'order'=>$this->full($company,$order),
        ]]);
    }

    public function cancel(Request $request, int $company, int $order): JsonResponse
    {
        $this->access($request,$company,'company.update');
        DB::transaction(function () use($company,$order): void {
            $row=$this->order($company,$order,true);
            if ($row->status !== 'ORDERED') abort(409,'Solo puede cancelarse una orden sin recepciones.');
            if (DB::table('purchase_receipts')->where('company_id',$company)->where('order_id',$order)->exists()) {
                abort(409,'La orden ya tiene recepciones.');
            }
            DB::table('purchase_orders')->where('company_id',$company)->where('id',$order)
                ->update(['status'=>'CANCELLED','updated_at'=>now()]);
        },3);
        return response()->json(['data'=>$this->full($company,$order)]);
    }
}
