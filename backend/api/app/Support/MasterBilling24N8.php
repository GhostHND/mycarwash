<?php
namespace App\Support;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

final class MasterBilling24N8 {
    public static function state(int $companyId): array {
        if (!Schema::hasTable('master_subscriptions_24n8')) {
            return ['status'=>'legacy','allowed'=>true,'days_until_due'=>null,'grace_remaining'=>null,'due_date'=>null];
        }
        $subscription=DB::table('master_subscriptions_24n8')->where('company_id',$companyId)->first();
        if (!$subscription) return ['status'=>'pending','allowed'=>false,'due_date'=>null,'days_until_due'=>null,'grace_remaining'=>null];
        if (in_array($subscription->status,['suspended','canceled','pending'],true)) {
            return ['status'=>$subscription->status,'allowed'=>false,'due_date'=>$subscription->due_date,
                'days_until_due'=>null,'grace_remaining'=>null];
        }
        $due=$subscription->due_date;
        if (!$due) return ['status'=>'active','allowed'=>true,'due_date'=>null,'days_until_due'=>null,'grace_remaining'=>null];
        $zone=$subscription->timezone ?: 'America/Tegucigalpa';
        $today=CarbonImmutable::now($zone)->startOfDay();
        $deadline=CarbonImmutable::parse($due,$zone)->startOfDay();
        $diff=(int)$today->diffInDays($deadline,false);
        if ($diff>=0) return ['status'=>'active','allowed'=>true,'due_date'=>$due,
            'days_until_due'=>$diff,'grace_remaining'=>null];
        $late=abs($diff);
        $grace=(int)$subscription->grace_days;
        if ($late<=$grace) return ['status'=>'past_due','allowed'=>true,'due_date'=>$due,
            'days_until_due'=>-$late,'grace_remaining'=>$grace-$late+1];
        return ['status'=>'suspended','allowed'=>false,'due_date'=>$due,
            'days_until_due'=>-$late,'grace_remaining'=>0];
    }
    public static function allowed(int $companyId): bool {
        if (!DB::table('companies')->where('id',$companyId)->where('is_active',true)->exists()) return false;
        return self::state($companyId)['allowed'];
    }
    public static function notice(int $companyId): ?array {
        $s=self::state($companyId);
        if ($s['status']==='past_due') return ['id'=>'auto-past-due','severity'=>'warning',
            'title'=>'Pago vencido: período de gracia',
            'body'=>'Tu plan venció el '.$s['due_date'].'. Quedan '.max(0,(int)$s['grace_remaining']).' día(s) de gracia. Confirma el pago con ADN Publicidad.'];
        if (!$s['allowed']) return ['id'=>'auto-blocked','severity'=>'critical',
            'title'=>'Servicio temporalmente suspendido','body'=>'El acceso está suspendido. Tus datos siguen guardados; contacta ADN Publicidad.'];
        if ($s['days_until_due']!==null && $s['days_until_due']<=7) return [
            'id'=>'auto-due-'.$s['due_date'],'severity'=>'warning','title'=>'Próxima renovación del plan',
            'body'=>'Tu próxima fecha de pago es '.$s['due_date'].' (faltan '.$s['days_until_due'].' día(s)).'];
        return null;
    }
}
