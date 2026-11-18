<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Libro de conciliación 24K: no altera ventas, efectivo ni apuntes históricos. */
class CompanyFinance24KController extends Controller
{
    private function permission(Request $request, int $company, string $permission): void
    {
        $user = $request->user();
        if (!$user) abort(401);
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $user->id)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($q): void {
            $q->on('r.id','=','ur.role_id')->on('r.company_id','=','ur.company_id');
        })->join('role_permission as rp','rp.role_id','=','r.id')
            ->join('permissions as p','p.id','=','rp.permission_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$user->id)->where('p.code',$permission)->exists();
        if (!$allowed) abort(403,'Permiso insuficiente.');
    }

    private function ready(): void
    {
        foreach (['finance_bank_openings_24k','finance_bank_entries_24k','finance_bank_closings_24k'] as $table) {
            if (!Schema::hasTable($table)) abort(503, 'Falta la migración de conciliación 24K.');
        }
    }

    private function bank(int $company, int $bankId, bool $locked = false): object
    {
        $q = DB::table('sale_bank_accounts')->where('company_id',$company)->where('id',$bankId)->whereNull('deleted_at');
        if ($locked) $q->lockForUpdate();
        return $q->first() ?? abort(404,'Cuenta bancaria no disponible.');
    }

    private function cents(mixed $value, string $field = 'amount'): int
    {
        $value = (string)$value;
        if (!preg_match('/^-?(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?$/D',$value)) {
            throw ValidationException::withMessages([$field=>'Importe inválido, máximo dos decimales.']);
        }
        $negative = str_starts_with($value,'-');
        $split = explode('.',ltrim($value,'-'),2);
        $n = ((int)$split[0]*100)+(int)str_pad($split[1] ?? '',2,'0');
        return $negative ? -$n : $n;
    }

    private function fmt(int $cents): string
    {
        $s=$cents<0?'-':'';
        $n=abs($cents);
        return $s.intdiv($n,100).'.'.str_pad((string)($n%100),2,'0',STR_PAD_LEFT);
    }

    private function interval(string $kind, string $date): array
    {
        $day=CarbonImmutable::createFromFormat('!Y-m-d',$date,'America/Tegucigalpa');
        if (!$day || $day->format('Y-m-d')!==$date) {
            throw ValidationException::withMessages(['date'=>'Fecha inválida.']);
        }
        $start=match ($kind) {
            'day'=>$day->startOfDay(),
            'week'=>$day->startOfWeek(CarbonImmutable::MONDAY),
            'month'=>$day->startOfMonth(),
            default=>throw ValidationException::withMessages(['period'=>'Período inválido.']),
        };
        $end=match ($kind) {
            'day'=>$start->addDay(), 'week'=>$start->addWeek(), 'month'=>$start->addMonth(),
        };
        return [$start,$end];
    }

    private function bounds(CarbonImmutable $start, CarbonImmutable $end): array
    {
        return [$start->utc()->format('Y-m-d H:i:s'),$end->utc()->format('Y-m-d H:i:s')];
    }

    private function sumMoney($query, string $column = 'amount'): int
    {
        $total = 0;
        // Suma por centavos: no usa aritmética flotante (especialmente SQLite).
        foreach ($query->pluck($column) as $amount) {
            $total += $this->cents($amount);
        }
        return $total;
    }

    /** Movimientos bancarios reales de ventas, POS y ajustes manuales, sin duplicar cobros. */
    private function flows(int $company, int $bankId, CarbonImmutable $start, CarbonImmutable $end): array
    {
        [$from,$to]=$this->bounds($start,$end);
        $wash=$this->sumMoney(DB::table('sale_bank_movements')->where('company_id',$company)
            ->where('bank_account_id',$bankId)->where('posted_at','>=',$from)->where('posted_at','<',$to));
        $pos=$this->sumMoney(DB::table('pos_sale_payments as p')
            ->join('pos_sales as s',function ($j):void{$j->on('s.id','=','p.sale_id')->on('s.company_id','=','p.company_id');})
            ->where('p.company_id',$company)->where('p.bank_account_id',$bankId)
            ->where('s.status','POSTED')->where('p.posted_at','>=',$from)->where('p.posted_at','<',$to)
            , 'p.amount');
        $manIn=$this->sumMoney(DB::table('finance_bank_entries_24k')->where('company_id',$company)
            ->where('bank_account_id',$bankId)->where('direction','IN')
            ->where('posted_date','>=',$start->format('Y-m-d'))->where('posted_date','<',$end->format('Y-m-d')));
        $manOut=$this->sumMoney(DB::table('finance_bank_entries_24k')->where('company_id',$company)
            ->where('bank_account_id',$bankId)->where('direction','OUT')
            ->where('posted_date','>=',$start->format('Y-m-d'))->where('posted_date','<',$end->format('Y-m-d')));
        return [$wash+$pos+$manIn,$manOut,$wash+$pos,$manIn];
    }

    private function opening(int $company, int $bankId): ?object
    {
        return DB::table('finance_bank_openings_24k')->where('company_id',$company)
            ->where('bank_account_id',$bankId)->first();
    }

    private function balance(int $company, int $bankId, CarbonImmutable $end): ?int
    {
        $initial=$this->opening($company,$bankId);
        if (!$initial) return null;
        $from=CarbonImmutable::createFromFormat('!Y-m-d',$initial->effective_date,'America/Tegucigalpa');
        if (!$from || $from >= $end) return null;
        [$credits,$debits]=$this->flows($company,$bankId,$from,$end);
        return $this->cents($initial->opening_balance,'opening_balance')+$credits-$debits;
    }

    private function periodData(Request $request): array
    {
        $data=$request->validate([
            'period'=>['sometimes',Rule::in(['day','week','month'])],
            'date'=>['sometimes','date_format:Y-m-d'],
            'branch_id'=>['sometimes','nullable','integer','min:1'],
        ]);
        $kind=$data['period']??'day';
        $date=$data['date']??now('America/Tegucigalpa')->format('Y-m-d');
        [$start,$end]=$this->interval($kind,$date);
        return [$kind,$start,$end,isset($data['branch_id'])?(int)$data['branch_id']:null];
    }

    public function overview(Request $request, int $company): JsonResponse
    {
        $this->permission($request,$company,'company.view');
        $this->ready();
        [$kind,$start,$end,$branchId]=$this->periodData($request);
        [$from,$to]=$this->bounds($start,$end);
        $banks=[];
        $accounts=DB::table('sale_bank_accounts')->where('company_id',$company)->whereNull('deleted_at')
            ->when($branchId!==null,fn($q)=>$q->where('branch_id',$branchId))->orderBy('bank_name')->get();
        $bankIn=0;$bankOut=0;
        foreach ($accounts as $account) {
            [$in,$out,$sales,$manual]=$this->flows($company,(int)$account->id,$start,$end);
            $bankIn+=$in;$bankOut+=$out;
            $close=DB::table('finance_bank_closings_24k')->where('company_id',$company)
                ->where('bank_account_id',$account->id)->where('period_kind',$kind)
                ->where('period_start',$start->format('Y-m-d'))->first();
            $accountsOpening=$this->opening($company,(int)$account->id);
            $final=$this->balance($company,(int)$account->id,$end);
            $banks[]=[
                'id'=>(int)$account->id,'alias'=>$account->alias,'bank_name'=>$account->bank_name,
                'account_last4'=>$account->account_last4,'branch_id'=>(int)$account->branch_id,
                'is_active'=>(bool)$account->is_active,'in'=>$this->fmt($in),'out'=>$this->fmt($out),
                'sales_in'=>$this->fmt($sales),'other_in'=>$this->fmt($manual),'net'=>$this->fmt($in-$out),
                'estimated_balance'=>$final===null?null:$this->fmt($final),
                'opening_set'=>$accountsOpening!==null,'opening_date'=>$accountsOpening?->effective_date,
                'closing'=> $close ? [
                    'id'=>(int)$close->id,'status'=>$close->status,
                    'expected'=>$close->expected_balance===null?null:$this->fmt($this->cents($close->expected_balance)),
                    'counted'=>$close->counted_balance===null?null:$this->fmt($this->cents($close->counted_balance)),
                    'difference'=>$close->difference_balance===null?null:$this->fmt($this->cents($close->difference_balance)),
                    'closed_at'=>$close->closed_at,
                    'post_close_change'=>$close->status==='CLOSED' && $final!==null
                        && $close->expected_balance!==null && $this->cents($close->expected_balance)!==$final,
                ]:null,
            ];
        }
        $registers=DB::table('cash_registers')->where('company_id',$company)->whereNull('deleted_at')
            ->when($branchId!==null,fn($q)=>$q->where('branch_id',$branchId))->orderBy('id')->get();
        $cash=[];$cashIn=0;$cashOut=0;
        foreach ($registers as $reg) {
            $mov=DB::table('cash_movements as m')->join('cash_sessions as s',function($j):void{
                $j->on('s.id','=','m.session_id')->on('s.company_id','=','m.company_id');
            })->where('m.company_id',$company)->where('s.register_id',$reg->id)
                ->whereNull('m.deleted_at')->where('m.created_at','>=',$from)->where('m.created_at','<',$to)
                ->get(['m.direction','m.amount']);
            $incoming=0;$outgoing=0;
            foreach ($mov as $entry) {
                $v=$this->cents($entry->amount);
                if ($entry->direction==='IN') $incoming+=$v; else $outgoing+=$v;
            }
            $cashIn+=$incoming;$cashOut+=$outgoing;
            $session=DB::table('cash_sessions')->where('company_id',$company)->where('register_id',$reg->id)
                ->whereNull('deleted_at')->orderByDesc('id')->first();
            $currentExpected=null;
            if ($session) {
                if ($session->status === 'OPEN') {
                    $all=DB::table('cash_movements')->where('company_id',$company)
                        ->where('session_id',$session->id)->whereNull('deleted_at')
                        ->get(['direction','amount']);
                    $currentExpected=$this->cents($session->opening_cash);
                    foreach ($all as $entry) {
                        $v=$this->cents($entry->amount);
                        $currentExpected+=($entry->direction==='IN'?$v:-$v);
                    }
                } else {
                    $currentExpected=$session->expected_cash===null?null:$this->cents($session->expected_cash);
                }
            }
            $cash[]=[
                'id'=>(int)$reg->id,'name'=>$reg->name,'code'=>$reg->code,'branch_id'=>(int)$reg->branch_id,
                'is_active'=>(bool)$reg->is_active,'in'=>$this->fmt($incoming),'out'=>$this->fmt($outgoing),
                'net'=>$this->fmt($incoming-$outgoing),
                'session_id'=>$session?->id,'session_status'=>$session?->status,
                'opening_cash'=>$session?$this->fmt($this->cents($session->opening_cash)):null,
                'expected_cash'=>$session?->expected_cash,
                'expected_current'=>$currentExpected===null?null:$this->fmt($currentExpected),
                'counted_cash'=>$session?->counted_cash,
                'difference_cash'=>$session?->difference_cash,
            ];
        }
        $closingRows=DB::table('cash_sessions')->where('company_id',$company)
            ->when($branchId!==null,function($q)use($branchId){
                $q->whereIn('register_id',DB::table('cash_registers')->where('branch_id',$branchId)->select('id'));
            })->where('status','CLOSED')->where('closed_at','>=',$from)->where('closed_at','<',$to)
            ->get(['difference_cash']);
        $cashClosingDifference=0;
        foreach ($closingRows as $closingRow) {
            $cashClosingDifference += $this->cents($closingRow->difference_cash??'0.00');
        }
        return response()->json(['data'=>[
            'cash_closings'=>['count'=>$closingRows->count(),'difference'=>$this->fmt($cashClosingDifference)],
            'period'=>$kind,'from'=>$start->format('Y-m-d'),'through'=>$end->subDay()->format('Y-m-d'),
            'date'=>$request->input('date',now('America/Tegucigalpa')->format('Y-m-d')),
            'timezone'=>'America/Tegucigalpa','cash'=>$cash,'banks'=>$banks,
            'totals'=>['cash_in'=>$this->fmt($cashIn),'cash_out'=>$this->fmt($cashOut),
                'bank_in'=>$this->fmt($bankIn),'bank_out'=>$this->fmt($bankOut)],
        ]]);
    }

    public function initializeBank(Request $request, int $company, int $bank): JsonResponse
    {
        $this->permission($request,$company,'company.update');$this->ready();
        $data=$request->validate(['opening_balance'=>['required','regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?$/D'],
            'effective_date'=>['required','date_format:Y-m-d']]);
        $this->cents($data['opening_balance'],'opening_balance');
        $result=DB::transaction(function() use($company,$bank,$data,$request){
            $this->bank($company,$bank,true);
            if ($this->opening($company,$bank)) throw ValidationException::withMessages(['opening_balance'=>'Esta cuenta ya tiene saldo inicial registrado. No se puede reemplazar.']);
            $id=DB::table('finance_bank_openings_24k')->insertGetId([
                'company_id'=>$company,'bank_account_id'=>$bank,'opening_balance'=>$data['opening_balance'],
                'effective_date'=>$data['effective_date'],'actor_user_id'=>$request->user()->id,
                'created_at'=>now(),'updated_at'=>now(),
            ]);
            return $id;
        });
        return response()->json(['data'=>['id'=>$result]],201);
    }

    public function bankEntry(Request $request,int $company,int $bank): JsonResponse
    {
        $this->permission($request,$company,'company.update');$this->ready();
        $data=$request->validate([
            'direction'=>['required',Rule::in(['IN','OUT'])],
            'amount'=>['required','regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?$/D'],
            'posted_date'=>['required','date_format:Y-m-d'],
            'reference'=>['sometimes','nullable','string','max:120'],
            'notes'=>['required','string','min:3','max:2000'],
            'idempotency_key'=>['required','string','min:20','max:120'],
        ]);
        if ($this->cents($data['amount'])<=0) throw ValidationException::withMessages(['amount'=>'Monto mayor a cero requerido.']);
        $hash=hash('sha256',json_encode([$bank,$data['direction'],$data['amount'],$data['posted_date'],$data['reference']??null,$data['notes']]));
        $id=DB::transaction(function() use($company,$bank,$request,$data,$hash){
            $existing=DB::table('finance_bank_entries_24k')->where('company_id',$company)->where('idempotency_key',$data['idempotency_key'])->first();
            if ($existing) {
                if ($existing->request_hash!==$hash) throw ValidationException::withMessages(['idempotency_key'=>'Clave ya utilizada con otro movimiento.']);
                return (int)$existing->id;
            }
            $account=$this->bank($company,$bank,true);
            if (!$account->is_active) throw ValidationException::withMessages(['bank_account_id'=>'Cuenta inactiva.']);
            $initial=$this->opening($company,$bank);
            if (!$initial || $data['posted_date']<$initial->effective_date) throw ValidationException::withMessages(['posted_date'=>'Establece saldo inicial; fecha no puede ser anterior a la apertura.']);
            foreach (DB::table('finance_bank_closings_24k')->where('company_id',$company)->where('bank_account_id',$bank)
                ->where('status','CLOSED')->get(['period_start','period_end']) as $closing) {
                if ($data['posted_date'] >= $closing->period_start && $data['posted_date'] <= $closing->period_end) {
                    throw ValidationException::withMessages(['posted_date'=>'Período conciliado: no se admiten movimientos retroactivos.']);
                }
            }
            return DB::table('finance_bank_entries_24k')->insertGetId([
                'company_id'=>$company,'bank_account_id'=>$bank,'posted_date'=>$data['posted_date'],
                'direction'=>$data['direction'],'amount'=>$data['amount'],
                'reference'=>$data['reference']??null,'notes'=>$data['notes'],
                'idempotency_key'=>$data['idempotency_key'],'request_hash'=>$hash,
                'actor_user_id'=>$request->user()->id,'created_at'=>now(),'updated_at'=>now(),
            ]);
        });
        return response()->json(['data'=>['id'=>$id]],201);
    }

    public function entries(Request $request,int $company,int $bank): JsonResponse
    {
        $this->permission($request,$company,'company.view');$this->ready();
        $this->bank($company,$bank);
        $rows=DB::table('finance_bank_entries_24k')->where('company_id',$company)
            ->where('bank_account_id',$bank)->orderByDesc('posted_date')->orderByDesc('id')->limit(100)
            ->get(['id','posted_date','direction','amount','reference','notes','created_at']);
        return response()->json(['data'=>$rows]);
    }

    public function openClosing(Request $request,int $company,int $bank): JsonResponse
    {
        $this->permission($request,$company,'company.update');$this->ready();
        $data=$request->validate(['period'=>['required',Rule::in(['day','week','month'])],'date'=>['required','date_format:Y-m-d']]);
        [$start,$end]=$this->interval($data['period'],$data['date']);
        $day=$start->format('Y-m-d');
        $id=DB::transaction(function()use($company,$bank,$data,$start,$end,$day,$request){
            $this->bank($company,$bank,true);
            $init=$this->opening($company,$bank);
            if(!$init || $init->effective_date>$day) throw ValidationException::withMessages(['date'=>'Configure un saldo inicial aplicable al período.']);
            $existing=DB::table('finance_bank_closings_24k')->where('company_id',$company)->where('bank_account_id',$bank)
                ->where('period_kind',$data['period'])->where('period_start',$day)->first();
            if($existing){
                if($existing->status==='CLOSED') throw ValidationException::withMessages(['date'=>'Período ya conciliado; el cierre es inmutable.']);
                return (int)$existing->id;
            }
            return DB::table('finance_bank_closings_24k')->insertGetId([
                'company_id'=>$company,'bank_account_id'=>$bank,'period_kind'=>$data['period'],
                'period_start'=>$day,'period_end'=>$end->subDay()->format('Y-m-d'),
                'status'=>'OPEN','opened_by'=>$request->user()->id,'opened_at'=>now(),
                'created_at'=>now(),'updated_at'=>now(),
            ]);
        });
        return response()->json(['data'=>['id'=>$id]],201);
    }

    public function closeClosing(Request $request,int $company,int $bank,int $closing): JsonResponse
    {
        $this->permission($request,$company,'company.update');$this->ready();
        $data=$request->validate(['counted_balance'=>['required','regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?$/D'],
            'notes'=>['sometimes','nullable','string','max:2000']]);
        $count=$this->cents($data['counted_balance'],'counted_balance');
        $row=DB::transaction(function()use($company,$bank,$closing,$count,$data,$request){
            $this->bank($company,$bank,true);
            $r=DB::table('finance_bank_closings_24k')->where('company_id',$company)
                ->where('bank_account_id',$bank)->where('id',$closing)->lockForUpdate()->first();
            if(!$r) abort(404,'Cuadre no disponible.');
            if($r->status!=='OPEN') throw ValidationException::withMessages(['closing'=>'Este cierre ya está confirmado y no se puede modificar.']);
            $start=CarbonImmutable::createFromFormat('!Y-m-d',$r->period_start,'America/Tegucigalpa');
            $end=CarbonImmutable::createFromFormat('!Y-m-d',$r->period_end,'America/Tegucigalpa')->addDay();
            if ($end>CarbonImmutable::now('America/Tegucigalpa')->addDay()->startOfDay()) {
                throw ValidationException::withMessages(['date'=>'No se puede cerrar un período futuro.']);
            }
            $expected=$this->balance($company,$bank,$end);
            if($expected===null) throw ValidationException::withMessages(['closing'=>'Sin saldo inicial para el período.']);
            DB::table('finance_bank_closings_24k')->where('id',$closing)->where('company_id',$company)->update([
                'status'=>'CLOSED','expected_balance'=>$this->fmt($expected),
                'counted_balance'=>$this->fmt($count),'difference_balance'=>$this->fmt($count-$expected),
                'notes'=>$data['notes']??null,'closed_by'=>$request->user()->id,
                'closed_at'=>now(),'updated_at'=>now(),
            ]);
            return ['id'=>$closing,'expected'=>$this->fmt($expected),'counted'=>$this->fmt($count),
                'difference'=>$this->fmt($count-$expected),'status'=>'CLOSED'];
        });
        return response()->json(['data'=>$row]);
    }
}
