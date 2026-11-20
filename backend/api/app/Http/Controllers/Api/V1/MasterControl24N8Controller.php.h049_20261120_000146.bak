<?php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MasterOperator24N8;
use App\Support\MasterBilling24N8;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

/** Panel comercial local; nunca confundir con pagos de lavados de los negocios. */
class MasterControl24N8Controller extends Controller {
    public function login(Request $request): JsonResponse {
        $d=$request->validate(['email'=>'required|email|max:255','password'=>'required|string']);
        $op=MasterOperator24N8::where('email',mb_strtolower($d['email']))->first();
        if (!$op || !$op->is_active || !Hash::check($d['password'],$op->password)) {
            throw ValidationException::withMessages(['email'=>['Credenciales maestras incorrectas.']]);
        }
        $token=$op->createToken('mycarwash-master',['master:all'],now()->addHours(8));
        return response()->json(['access_token'=>$token->plainTextToken,'expires_at'=>now()->addHours(8)->toIso8601String(),
            'user'=>['name'=>$op->name,'email'=>$op->email]]);
    }
    public function logout(Request $request):JsonResponse {
        $token=$request->user()->currentAccessToken();
        if ($token instanceof PersonalAccessToken) $token->delete();
        return response()->json(['message'=>'Sesión maestra cerrada.']);
    }
    public function overview():JsonResponse {
        $companies=DB::table('companies as c')->leftJoin('master_subscriptions_24n8 as s','s.company_id','=','c.id')
            ->leftJoin('master_plans_24n8 as p','p.id','=','s.master_plan_id')
            ->leftJoin('master_customers_24n8 as m','m.id','=','s.master_customer_id')
            ->select('c.id','c.name','c.slug','c.is_active','s.status as stored_status','s.due_date','s.grace_days',
                's.master_plan_id','s.master_customer_id','p.name as plan_name','m.name as customer_name')
            ->orderBy('c.id')->get()->map(function ($row) {
                $billing=MasterBilling24N8::state((int)$row->id);
                return array_merge((array)$row,['billing'=>$billing]);
            });
        return response()->json(['companies'=>$companies,
            'customers'=>DB::table('master_customers_24n8')->orderBy('name')->get(),
            'plans'=>DB::table('master_plans_24n8')->orderBy('id')->get(),
            'invoices'=>DB::table('master_invoices_24n8')->orderByDesc('id')->limit(300)->get(),
            'payments'=>DB::table('master_payments_24n8')->orderByDesc('id')->limit(300)->get(),
            'notices'=>DB::table('master_notices_24n8')->orderByDesc('id')->limit(300)->get()]);
    }
    private function audit(Request $req,string $action,string $target,array $details=[]):void {
        // El historial se almacena sin credenciales ni información de tarjetas.
        DB::table('master_audit_24n8')->insert(['master_operator_id'=>$req->user()->id,
            'action'=>$action,'target'=>$target,'details'=>json_encode($details), 'created_at'=>now()]);
    }
    public function customerCreate(Request $request):JsonResponse {
        $d=$request->validate(['name'=>'required|string|min:2|max:180','email'=>'nullable|email|max:255',
            'phone'=>'nullable|string|max:40','tax_id'=>'nullable|string|max:80',
            'notes'=>'nullable|string|max:2000']);
        $id=DB::table('master_customers_24n8')->insertGetId($d+['is_active'=>true,'created_at'=>now(),'updated_at'=>now()]);
        $this->audit($request,'customer.created','customer:'.$id); return response()->json(['id'=>$id],201);
    }
    public function customerUpdate(Request $request,int $customer):JsonResponse {
        abort_unless(DB::table('master_customers_24n8')->where('id',$customer)->exists(),404);
        $d=$request->validate(['name'=>'sometimes|required|string|min:2|max:180','email'=>'nullable|email|max:255',
            'phone'=>'nullable|string|max:40','tax_id'=>'nullable|string|max:80','notes'=>'nullable|string|max:2000',
            'is_active'=>'sometimes|boolean']);
        DB::table('master_customers_24n8')->where('id',$customer)->update($d+['updated_at'=>now()]);
        $this->audit($request,'customer.updated','customer:'.$customer);return response()->json(['ok'=>true]);
    }
    public function customerDelete(Request $request,int $customer):JsonResponse {
        abort_unless(DB::table('master_customers_24n8')->where('id',$customer)->exists(),404);
        DB::table('master_customers_24n8')->where('id',$customer)->update(['is_active'=>false,'updated_at'=>now()]);
        $this->audit($request,'customer.archived','customer:'.$customer);return response()->json(['ok'=>true]);
    }
    private function planRules(bool $create):array {
        return ['name'=>[$create?'required':'sometimes','string','min:2','max:100'],
            'monthly_price'=>'nullable|numeric|min:0|max:9999999999',
            'currency'=>'sometimes|in:HNL,USD',
            'features'=>'nullable|array',
            'features.operations'=>'sometimes|boolean', 'features.monitor'=>'sometimes|boolean',
            'features.marketing_site'=>'sometimes|boolean','features.editor'=>'sometimes|boolean',
            'is_active'=>'sometimes|boolean'];
    }
    public function planCreate(Request $request):JsonResponse {
        $d=$request->validate($this->planRules(true));
        $d['features']=json_encode($d['features']??[]);
        $id=DB::table('master_plans_24n8')->insertGetId($d+['currency'=>'HNL','is_active'=>true,
            'created_at'=>now(),'updated_at'=>now()]);
        $this->audit($request,'plan.created','plan:'.$id);return response()->json(['id'=>$id],201);
    }
    public function planUpdate(Request $request,int $plan):JsonResponse {
        abort_unless(DB::table('master_plans_24n8')->where('id',$plan)->exists(),404);
        $d=$request->validate($this->planRules(false));
        if (array_key_exists('features',$d)) $d['features']=json_encode($d['features']??[]);
        DB::table('master_plans_24n8')->where('id',$plan)->update($d+['updated_at'=>now()]);
        $this->audit($request,'plan.updated','plan:'.$plan);return response()->json(['ok'=>true]);
    }
    public function planDelete(Request $request,int $plan):JsonResponse {
        abort_unless(DB::table('master_plans_24n8')->where('id',$plan)->exists(),404);
        DB::table('master_plans_24n8')->where('id',$plan)->update(['is_active'=>false,'updated_at'=>now()]);
        $this->audit($request,'plan.archived','plan:'.$plan);return response()->json(['ok'=>true]);
    }
    private function companyData():array {
        return ['name'=>'required|string|min:3|max:180','owner_name'=>'required|string|min:3|max:180',
            'owner_email'=>'required|email|max:255','owner_password'=>'required|string|min:12|max:128',
            'customer_id'=>'nullable|integer|exists:master_customers_24n8,id',
            'plan_id'=>'nullable|integer|exists:master_plans_24n8,id',
            'due_date'=>'nullable|date_format:Y-m-d'];
    }
    public function companyCreate(Request $request):JsonResponse {
        $d=$request->validate($this->companyData());
        if (!preg_match('/[A-Z]/',$d['owner_password'])||!preg_match('/[a-z]/',$d['owner_password'])||!preg_match('/[0-9]/',$d['owner_password'])) {
            throw ValidationException::withMessages(['owner_password'=>['La contraseña requiere mayúscula, minúscula y número.']]);
        }
        $slug=Str::slug($d['name']);
        if (DB::table('companies')->where('slug',$slug)->exists()||DB::table('users')->where('email',mb_strtolower($d['owner_email']))->exists()) {
            throw ValidationException::withMessages(['name'=>['La empresa o el correo del propietario ya existen.']]);
        }
        $created=DB::transaction(function () use($d,$slug) {
            $now=now();$userId=DB::table('users')->insertGetId(['name'=>$d['owner_name'],
                'email'=>mb_strtolower($d['owner_email']),'password'=>Hash::make($d['owner_password']),
                'created_at'=>$now,'updated_at'=>$now]);
            $company=DB::table('companies')->insertGetId(['public_id'=>(string)Str::uuid(),
                'name'=>$d['name'],'slug'=>$slug,'is_active'=>false,'created_at'=>$now,'updated_at'=>$now]);
            $branch=DB::table('branches')->insertGetId(['company_id'=>$company,'name'=>'Sucursal principal',
                'slug'=>'principal','timezone'=>'America/Tegucigalpa','is_active'=>true,
                'created_at'=>$now,'updated_at'=>$now]);
            DB::table('company_user')->insert(['company_id'=>$company,'user_id'=>$userId,'status'=>'active',
                'access_all_branches'=>true,'created_at'=>$now,'updated_at'=>$now]);
            DB::table('branch_user')->insert(['company_id'=>$company,'branch_id'=>$branch,'user_id'=>$userId,
                'created_at'=>$now,'updated_at'=>$now]);
            $roleId=DB::table('roles')->insertGetId(['company_id'=>$company,'name'=>'Propietario',
                'code'=>'owner','is_system'=>true,'created_at'=>$now,'updated_at'=>$now]);
            DB::table('user_roles')->insert(['company_id'=>$company,'role_id'=>$roleId,'user_id'=>$userId,
                'created_at'=>$now,'updated_at'=>$now]);
            foreach (array_chunk(DB::table('permissions')->pluck('id')->all(),100) as $chunk) {
                DB::table('role_permission')->insert(array_map(fn($permissionId)=>['role_id'=>$roleId,
                    'permission_id'=>$permissionId,'created_at'=>$now,'updated_at'=>$now],$chunk));
            }
            DB::table('company_profiles')->insert(['company_id'=>$company,'commercial_name'=>$d['name'],
                'business_category'=>'carwash','created_at'=>$now,'updated_at'=>$now]);
            DB::table('company_brandings')->insert(['company_id'=>$company,'created_at'=>$now,'updated_at'=>$now]);
            DB::table('company_preferences')->insert(['company_id'=>$company,'created_at'=>$now,'updated_at'=>$now]);
            DB::table('user_preferences')->insert(['user_id'=>$userId,'theme_mode'=>'system','locale'=>'es-HN',
                'created_at'=>$now,'updated_at'=>$now]);
            DB::table('master_subscriptions_24n8')->insert(['company_id'=>$company,
                'master_customer_id'=>$d['customer_id']??null,'master_plan_id'=>$d['plan_id']??null,
                'status'=>'pending','due_date'=>$d['due_date']??null,'grace_days'=>4,
                'timezone'=>'America/Tegucigalpa','created_at'=>$now,'updated_at'=>$now]);
            return $company;
        },3);
        $this->audit($request,'company.created','company:'.$created);
        return response()->json(['id'=>$created,'status'=>'pending','message'=>'Empresa creada; activar desde el panel maestro.'],201);
    }
    public function companyUpdate(Request $request,int $company):JsonResponse {
        abort_unless(DB::table('companies')->where('id',$company)->exists(),404);
        $d=$request->validate(['name'=>'sometimes|required|string|min:3|max:180',
            'customer_id'=>'nullable|integer|exists:master_customers_24n8,id',
            'plan_id'=>'nullable|integer|exists:master_plans_24n8,id',
            'due_date'=>'nullable|date_format:Y-m-d',
            'status'=>'sometimes|in:pending,active,canceled,suspended',
            'notes'=>'nullable|string|max:2000']);
        if (($d['status'] ?? '') === 'active') {
            $existingCompany=DB::table('companies')->where('id',$company)->first();
            if ($existingCompany && !$existingCompany->is_active) {
                $sub=DB::table('master_subscriptions_24n8')->where('company_id',$company)->first();
                $planId=$d['plan_id'] ?? $sub?->master_plan_id;
                $date=$d['due_date'] ?? $sub?->due_date;
                $plan=$planId ? DB::table('master_plans_24n8')->where('id',$planId)->first():null;
                abort_unless($plan && $plan->is_active && $plan->monthly_price !== null && $date,422,
                    'Para activar una empresa nueva, configura plan, precio y vencimiento.');
            }
        }
        DB::transaction(function () use($company,$d){
            if(isset($d['name'])) DB::table('companies')->where('id',$company)->update(['name'=>$d['name'],'updated_at'=>now()]);
            $updates=[];
            foreach(['customer_id'=>'master_customer_id','plan_id'=>'master_plan_id',
                'due_date'=>'due_date','status'=>'status','notes'=>'notes'] as $key=>$col) {
                if(array_key_exists($key,$d)) $updates[$col]=$d[$key];
            }
            if($updates) DB::table('master_subscriptions_24n8')->updateOrInsert(['company_id'=>$company],
                $updates+['updated_at'=>now()]);
            if(isset($d['status'])) DB::table('companies')->where('id',$company)->update([
                'is_active'=>$d['status']==='active','updated_at'=>now()]);
        });
        $this->audit($request,'company.updated','company:'.$company,array_diff_key($d,array_flip(['notes'])));
        return response()->json(['ok'=>true,'billing'=>MasterBilling24N8::state($company)]);
    }
    public function companyDelete(Request $request,int $company):JsonResponse {
        abort_unless(DB::table('companies')->where('id',$company)->exists(),404);
        DB::transaction(function () use($company){
            DB::table('companies')->where('id',$company)->update(['is_active'=>false,'updated_at'=>now()]);
            DB::table('master_subscriptions_24n8')->where('company_id',$company)->update([
                'status'=>'canceled','updated_at'=>now()]);
        });
        $this->audit($request,'company.archived','company:'.$company);
        return response()->json(['ok'=>true,'message'=>'Empresa archivada; no se eliminaron datos operativos.']);
    }
    public function invoiceCreate(Request $request):JsonResponse {
        $d=$request->validate(['company_id'=>'required|integer|exists:companies,id',
            'amount'=>'required|numeric|gt:0|max:9999999999',
            'due_date'=>'required|date_format:Y-m-d', 'coverage_until'=>'required|date_format:Y-m-d|after_or_equal:due_date',
            'notes'=>'nullable|string|max:2000']);
        $sub=DB::table('master_subscriptions_24n8')->where('company_id',$d['company_id'])->first();
        abort_unless($sub && $sub->master_plan_id,422,'Primero asigna un plan a la empresa.');
        $id=DB::table('master_invoices_24n8')->insertGetId([
            'company_id'=>$d['company_id'],'master_plan_id'=>$sub->master_plan_id,
            'reference'=>'ADN-MCW-'.strtoupper(Str::random(12)), 'amount'=>$d['amount'],'currency'=>'HNL',
            'due_date'=>$d['due_date'],'coverage_until'=>$d['coverage_until'],
            'status'=>'pending','notes'=>$d['notes']??null,'created_at'=>now(),'updated_at'=>now()]);
        $this->audit($request,'invoice.created','invoice:'.$id);return response()->json(['id'=>$id],201);
    }
    public function invoiceUpdate(Request $request,int $invoice):JsonResponse {
        $i=DB::table('master_invoices_24n8')->where('id',$invoice)->first();abort_unless($i,404);
        abort_unless($i->status==='pending',409,'Una factura pagada o anulada es inmutable.');
        $d=$request->validate(['amount'=>'sometimes|numeric|gt:0|max:9999999999',
            'due_date'=>'sometimes|date_format:Y-m-d','coverage_until'=>'sometimes|date_format:Y-m-d',
            'notes'=>'nullable|string|max:2000']);
        $confirmed=(float)DB::table('master_payments_24n8')->where('master_invoice_id',$invoice)->where('status','confirmed')->sum('amount');
        if(isset($d['amount']) && (float)$d['amount'] < $confirmed) abort(409,'El importe no puede ser menor a los pagos confirmados.');
        DB::table('master_invoices_24n8')->where('id',$invoice)->update($d+['updated_at'=>now()]);
        $this->audit($request,'invoice.updated','invoice:'.$invoice);return response()->json(['ok'=>true]);
    }
    public function invoiceDelete(Request $request,int $invoice):JsonResponse {
        $i=DB::table('master_invoices_24n8')->where('id',$invoice)->first();abort_unless($i,404);
        abort_unless($i->status==='pending' && !DB::table('master_payments_24n8')->where('master_invoice_id',$invoice)->where('status','confirmed')->exists(),409);
        DB::table('master_invoices_24n8')->where('id',$invoice)->update(['status'=>'void','updated_at'=>now()]);
        $this->audit($request,'invoice.voided','invoice:'.$invoice);return response()->json(['ok'=>true]);
    }
    public function paymentCreate(Request $request):JsonResponse {
        $d=$request->validate(['invoice_id'=>'required|integer|exists:master_invoices_24n8,id',
            'amount'=>'required|numeric|gt:0|max:9999999999','method'=>'required|string|max:45',
            'reference'=>'nullable|string|max:130','notes'=>'nullable|string|max:2000']);
        $invoice=DB::table('master_invoices_24n8')->where('id',$d['invoice_id'])->first();
        abort_unless($invoice && $invoice->status==='pending',409,'La factura no acepta pagos.');
        $id=DB::table('master_payments_24n8')->insertGetId(['master_invoice_id'=>$d['invoice_id'],
            'amount'=>$d['amount'],'method'=>$d['method'],'reference'=>$d['reference']??null,
            'notes'=>$d['notes']??null,'status'=>'pending','created_at'=>now(),'updated_at'=>now()]);
        $this->audit($request,'payment.recorded','payment:'.$id);return response()->json(['id'=>$id],201);
    }
    public function paymentUpdate(Request $request,int $payment):JsonResponse {
        $p=DB::table('master_payments_24n8')->where('id',$payment)->first();abort_unless($p,404);
        abort_unless($p->status==='pending',409,'Los pagos confirmados son inmutables.');
        $d=$request->validate(['amount'=>'sometimes|numeric|gt:0|max:9999999999',
            'method'=>'sometimes|string|max:45','reference'=>'nullable|string|max:130',
            'notes'=>'nullable|string|max:2000']);
        DB::table('master_payments_24n8')->where('id',$payment)->update($d+['updated_at'=>now()]);
        $this->audit($request,'payment.updated','payment:'.$payment);return response()->json(['ok'=>true]);
    }
    public function paymentConfirm(Request $request,int $payment):JsonResponse {
        $result=DB::transaction(function () use($request,$payment) {
            $p=DB::table('master_payments_24n8')->where('id',$payment)->lockForUpdate()->first();abort_unless($p,404);
            abort_unless($p->status==='pending',409,'Este pago ya fue procesado.');
            $invoice=DB::table('master_invoices_24n8')->where('id',$p->master_invoice_id)->lockForUpdate()->first();
            abort_unless($invoice && $invoice->status==='pending',409,'Factura no disponible.');
            $total=(float)DB::table('master_payments_24n8')->where('master_invoice_id',$invoice->id)
                ->where('status','confirmed')->sum('amount') + (float)$p->amount;
            abort_if($total > (float)$invoice->amount+0.001,409,'El pago excede el importe pendiente.');
            DB::table('master_payments_24n8')->where('id',$payment)->update(['status'=>'confirmed',
                'confirmed_by'=>$request->user()->id,'paid_at'=>now(),'updated_at'=>now()]);
            if ($total+0.001 >=(float)$invoice->amount) {
                DB::table('master_invoices_24n8')->where('id',$invoice->id)->update(['status'=>'paid','paid_at'=>now(),'updated_at'=>now()]);
                $sub=DB::table('master_subscriptions_24n8')->where('company_id',$invoice->company_id)->lockForUpdate()->first();
                if($sub) {
                    $coverage=$invoice->coverage_until;
                    $date=($coverage && (!$sub->due_date || $coverage > $sub->due_date)) ? $coverage : $sub->due_date;
                    DB::table('master_subscriptions_24n8')->where('company_id',$invoice->company_id)->update([
                        'due_date'=>$date,'status'=>'active','updated_at'=>now()]);
                    DB::table('companies')->where('id',$invoice->company_id)->update(['is_active'=>true,'updated_at'=>now()]);
                }
            }
            return ['invoice_id'=>$invoice->id,'total_confirmed'=>$total,'fully_paid'=>$total+0.001 >=(float)$invoice->amount];
        },3);
        $this->audit($request,'payment.confirmed','payment:'.$payment,$result);
        return response()->json($result);
    }
    public function paymentDelete(Request $request,int $payment):JsonResponse {
        $p=DB::table('master_payments_24n8')->where('id',$payment)->first();abort_unless($p,404);
        abort_unless($p->status==='pending',409,'No se permite eliminar pagos confirmados.');
        DB::table('master_payments_24n8')->where('id',$payment)->update(['status'=>'void','updated_at'=>now()]);
        $this->audit($request,'payment.voided','payment:'.$payment);return response()->json(['ok'=>true]);
    }
    public function noticeCreate(Request $request):JsonResponse {
        $d=$request->validate(['company_id'=>'nullable|integer|exists:companies,id','title'=>'required|string|max:160',
            'body'=>'required|string|max:4000','severity'=>'sometimes|in:info,warning,critical',
            'starts_at'=>'nullable|date','expires_at'=>'nullable|date|after:starts_at']);
        $id=DB::table('master_notices_24n8')->insertGetId($d+['severity'=>'info','is_active'=>true,
            'created_at'=>now(),'updated_at'=>now()]);
        $this->audit($request,'notice.created','notice:'.$id);return response()->json(['id'=>$id],201);
    }
    public function noticeUpdate(Request $request,int $notice):JsonResponse {
        abort_unless(DB::table('master_notices_24n8')->where('id',$notice)->exists(),404);
        $d=$request->validate(['company_id'=>'nullable|integer|exists:companies,id',
            'title'=>'sometimes|string|max:160','body'=>'sometimes|string|max:4000',
            'severity'=>'sometimes|in:info,warning,critical', 'is_active'=>'sometimes|boolean',
            'starts_at'=>'nullable|date','expires_at'=>'nullable|date']);
        DB::table('master_notices_24n8')->where('id',$notice)->update($d+['updated_at'=>now()]);
        $this->audit($request,'notice.updated','notice:'.$notice);return response()->json(['ok'=>true]);
    }
    public function noticeDelete(Request $request,int $notice):JsonResponse {
        abort_unless(DB::table('master_notices_24n8')->where('id',$notice)->exists(),404);
        DB::table('master_notices_24n8')->where('id',$notice)->update(['is_active'=>false,'updated_at'=>now()]);
        $this->audit($request,'notice.archived','notice:'.$notice);return response()->json(['ok'=>true]);
    }
    public function companyAlerts(Request $request,int $company):JsonResponse {
        $userId=(int)$request->user()->id;
        $member=DB::table('company_user')->where('company_id',$company)->where('user_id',$userId)
            ->where('status','active')->exists();abort_unless($member,403);
        $role=DB::table('user_roles as ur')->join('roles as r','r.id','=','ur.role_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$userId)
            ->whereIn('r.code',['owner','admin','manager'])->exists();
        if(!$role) return response()->json(['notices'=>[]]);
        $now=now();
        $notices=DB::table('master_notices_24n8 as n')->leftJoin('master_notice_reads_24n8 as r',function($join) use($userId){
            $join->on('r.notice_id','=','n.id')->where('r.user_id','=',$userId);
        })->where(function($q)use($company){$q->where('n.company_id',$company)->orWhereNull('n.company_id');})
            ->where('n.is_active',true)->where(function($q)use($now){$q->whereNull('n.starts_at')->orWhere('n.starts_at','<=',$now);})
            ->where(function($q)use($now){$q->whereNull('n.expires_at')->orWhere('n.expires_at','>=',$now);})
            ->whereNull('r.id')->select('n.id','n.title','n.body','n.severity')->orderByDesc('n.id')->limit(20)->get()->toArray();
        $automatic=MasterBilling24N8::notice($company);
        if($automatic) array_unshift($notices,$automatic);
        return response()->json(['notices'=>$notices,'billing'=>MasterBilling24N8::state($company)]);
    }
    public function noticeRead(Request $request,int $company,int $notice):JsonResponse {
        abort_unless(DB::table('company_user')->where('company_id',$company)->where('user_id',$request->user()->id)->where('status','active')->exists(),403);
        abort_unless(DB::table('master_notices_24n8')->where('id',$notice)->where('is_active',true)
            ->where(function($q)use($company){$q->whereNull('company_id')->orWhere('company_id',$company);})->exists(),404);
        DB::table('master_notice_reads_24n8')->updateOrInsert(['notice_id'=>$notice,'user_id'=>$request->user()->id],['read_at'=>now()]);
        return response()->json(['ok'=>true]);
    }
}
