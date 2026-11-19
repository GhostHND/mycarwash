<?php
namespace App\Console\Commands;

use App\Models\MasterOperator24N8;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;

class SetupMaster24N8 extends Command {
    protected $signature='mycarwash:master-setup {--email= : Correo de la cuenta maestra}';
    protected $description='Crear o recuperar la cuenta maestra con contraseña oculta';
    public function handle(): int {
        if (!Schema::hasTable('master_operators_24n8')) { $this->error('Ejecuta primero php artisan migrate.'); return 1; }
        $email=mb_strtolower(trim((string)($this->option('email') ?: $this->ask('Correo maestro'))));
        if (!filter_var($email,FILTER_VALIDATE_EMAIL)) {$this->error('Correo inválido.');return 1;}
        $existing=MasterOperator24N8::where('email',$email)->first();
        if ($existing && !$this->confirm('La cuenta existe. ¿Restablecer su contraseña?',false)) return 1;
        $name=$existing?->name ?: trim((string)$this->ask('Nombre del administrador maestro','ADN Publicidad'));
        $password=(string)$this->secret('Contraseña nueva (12+ caracteres; mayúscula, minúscula, número y símbolo)');
        $confirm=(string)$this->secret('Repita la contraseña');
        if ($password!==$confirm || strlen($password)<12 || !preg_match('/[A-Z]/',$password) ||
            !preg_match('/[a-z]/',$password) || !preg_match('/[0-9]/',$password) ||
            !preg_match('/[^A-Za-z0-9]/',$password)) {$this->error('Las contraseñas no coinciden o no cumplen seguridad.');return 1;}
        $operator=MasterOperator24N8::updateOrCreate(['email'=>$email],[
            'name'=>$name,'password'=>Hash::make($password),'is_active'=>true]);
        $operator->tokens()->delete();
        $this->info('Cuenta maestra configurada. Se invalidaron sesiones antiguas.');
        return 0;
    }
}
