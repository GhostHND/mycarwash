<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\V1\CompanyWashMonitor24B2Controller;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

final class MonitorCompletion24N5Test extends TestCase
{
    use DatabaseTransactions;

    public function test_only_global_recent_events_in_same_company_and_branch_are_returned(): void
    {
        if (DB::connection()->getDriverName() !== 'sqlite' || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Solo SQLite :memory:');
        }
        foreach (['company_entity_photos', 'wash_order_events', 'wash_assignments', 'wash_orders',
            'wash_bays', 'wash_services', 'vehicles', 'employees'] as $table) Schema::dropIfExists($table);
        Schema::create('wash_orders', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('vehicle_id'); $t->unsignedBigInteger('service_id');
            $t->unsignedBigInteger('bay_id')->nullable();
        });
        Schema::create('vehicles', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->string('brand'); $t->string('model'); $t->string('plate');
        });
        Schema::create('wash_services', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
        });
        Schema::create('wash_bays', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
        });
        Schema::create('employees', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('full_name');
        });
        Schema::create('wash_assignments', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('order_id');
            $t->unsignedBigInteger('employee_id');
        });
        Schema::create('wash_order_events', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('order_id');
            $t->string('to_status'); $t->timestamp('occurred_at');
        });
        DB::table('vehicles')->insert([['id'=>1, 'company_id'=>1, 'brand'=>'Honda', 'model'=>'Civic', 'plate'=>'HND001'],
            ['id'=>2, 'company_id'=>2, 'brand'=>'Toyota', 'model'=>'Hilux', 'plate'=>'AJENA']]);
        DB::table('wash_services')->insert([['id'=>1, 'company_id'=>1, 'name'=>'Básico'],
            ['id'=>2, 'company_id'=>2, 'name'=>'General']]);
        DB::table('wash_bays')->insert(['id'=>1, 'company_id'=>1, 'name'=>'Puesto 2']);
        DB::table('employees')->insert(['id'=>1, 'company_id'=>1, 'full_name'=>'David']);
        // SQLite requiere que todas las filas de un INSERT multiple tengan
        // exactamente las mismas columnas. Para las ordenes sin puesto, se
        // utiliza NULL de forma explicita (no un puesto ficticio).
        $washOrderRows = [
            ['id'=>10, 'company_id'=>1, 'branch_id'=>1, 'vehicle_id'=>1, 'service_id'=>1, 'bay_id'=>1],
            ['id'=>11, 'company_id'=>1, 'branch_id'=>2, 'vehicle_id'=>1, 'service_id'=>1, 'bay_id'=>null],
            ['id'=>12, 'company_id'=>2, 'branch_id'=>3, 'vehicle_id'=>2, 'service_id'=>2, 'bay_id'=>null],
        ];
        foreach ($washOrderRows as $row) {
            $this->assertSame(array_keys($washOrderRows[0]), array_keys($row),
                'Todas las ordenes de la prueba deben tener las mismas columnas.');
        }
        DB::table('wash_orders')->insert($washOrderRows);
        DB::table('wash_assignments')->insert(['company_id'=>1, 'order_id'=>10, 'employee_id'=>1]);
        DB::table('wash_order_events')->insert([
            ['id'=>1,'company_id'=>1,'order_id'=>10,'to_status'=>'EN_PROCESO','occurred_at'=>now()],
            ['id'=>2,'company_id'=>1,'order_id'=>10,'to_status'=>'TERMINADO','occurred_at'=>now()],
            ['id'=>3,'company_id'=>1,'order_id'=>11,'to_status'=>'TERMINADO','occurred_at'=>now()],
            ['id'=>4,'company_id'=>2,'order_id'=>12,'to_status'=>'TERMINADO','occurred_at'=>now()],
            ['id'=>5,'company_id'=>1,'order_id'=>10,'to_status'=>'TERMINADO','occurred_at'=>now()->subHour()],
        ]);
        $controller = new CompanyWashMonitor24B2Controller();
        $method = new \ReflectionMethod($controller, 'recentCompletions');
        $events = $method->invoke($controller, 1, 1);
        $this->assertCount(1, $events);
        $this->assertSame(2, $events[0]['event_id']);
        $this->assertSame('Honda', $events[0]['brand']);
        $this->assertSame('David', $events[0]['washers'][0]);
        $this->assertSame('Puesto 2', $events[0]['bay']);
    }
}
