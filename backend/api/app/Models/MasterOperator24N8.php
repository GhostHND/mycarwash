<?php
namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

class MasterOperator24N8 extends Authenticatable {
    use HasApiTokens;
    protected $table = 'master_operators_24n8';
    protected $fillable = ['name','email','password','is_active'];
    protected $hidden = ['password'];
    protected function casts(): array { return ['is_active'=>'boolean','password'=>'hashed']; }
}
