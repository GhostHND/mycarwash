<?php
namespace App\Http\Middleware;

use App\Models\MasterOperator24N8;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class MasterOnly24N8 {
    public function handle(Request $request,Closure $next):Response {
        $user=$request->user();
        abort_unless($user instanceof MasterOperator24N8 && $user->is_active &&
            $user->currentAccessToken() && $user->tokenCan('master:all'),403,
            'Se requiere una sesión maestra autorizada.');
        return $next($request);
    }
}
