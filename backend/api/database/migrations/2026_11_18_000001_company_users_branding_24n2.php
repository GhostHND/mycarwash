<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('employee_user', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->foreignId('employee_id')->constrained('employees')->restrictOnDelete();
            $t->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $t->timestamps();
            $t->unique(['company_id', 'employee_id']);
            $t->unique(['company_id', 'user_id']);
        });
        Schema::table('company_brandings', function (Blueprint $t): void {
            $t->string('card_color', 7)->default('#102027');
            $t->string('border_color', 7)->default('#21333B');
            $t->string('field_color', 7)->default('#15262D');
            $t->string('icon_color', 7)->default('#0FA7B4');
            $t->string('heading_color', 7)->default('#F5FAFC');
            $t->string('hover_color', 7)->default('#16343C');
            $t->string('selected_color', 7)->default('#17454D');
            $t->unsignedTinyInteger('visual_theme_version')->default(0);
        });
        $now = now();
        foreach (['dashboard','washes','schedule','customers','staff','inventory','cash','sales','reports','company','users'] as $module) {
            foreach (['view','create','edit','execute'] as $action) {
                $code = 'nav.'.$module.'.'.$action;
                DB::table('permissions')->updateOrInsert(['code' => $code], [
                    'module' => $module, 'description' => ucfirst($module).' - '.$action,
                    'updated_at' => $now, 'created_at' => $now,
                ]);
            }
        }
        $permissions = DB::table('permissions')->where('code', 'like', 'nav.%')->pluck('id');
        $owners = DB::table('roles')->where('code', 'owner')->where('is_system', true)->pluck('id');
        foreach ($owners as $roleId) foreach ($permissions as $permissionId) {
            DB::table('role_permission')->updateOrInsert([
                'role_id' => $roleId, 'permission_id' => $permissionId,
            ], ['updated_at' => $now, 'created_at' => $now]);
        }
    }

    public function down(): void
    {
        $ids = DB::table('permissions')->where('code', 'like', 'nav.%')->pluck('id');
        DB::table('role_permission')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
        Schema::table('company_brandings', function (Blueprint $t): void {
            $t->dropColumn(['card_color','border_color','field_color','icon_color','heading_color','hover_color','selected_color', 'visual_theme_version']);
        });
        Schema::dropIfExists('employee_user');
    }
};
