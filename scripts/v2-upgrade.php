<?php

/*
 * Prepares a Cachet v2.x database for the Cachet v3 migrations.
 *
 * Cachet v3 ships the v2 migrations and data migrations, but its own
 * Laravel scaffolding migrations (users, jobs, failed_jobs) collide with
 * tables that already exist in a v2 database. This script runs before
 * "php artisan migrate" and is a no-op unless a v2 schema is detected.
 *
 * Run from the application directory: php /usr/local/share/cachet/v2-upgrade.php
 */

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

require getcwd().'/vendor/autoload.php';

$app = require getcwd().'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$log = fn (string $message) => fwrite(STDOUT, "[v2-upgrade] {$message}\n");

// v2 users have a "username" column; v3 users have "name".
if (! Schema::hasTable('migrations') || ! Schema::hasTable('users') || ! Schema::hasColumn('users', 'username')) {
    $log('no Cachet v2 schema found, nothing to do');
    exit(0);
}

$log('Cachet v2 schema found, preparing it for the v3 migrations');

$markAsRun = function (string $migration) use ($log) {
    if (DB::table('migrations')->where('migration', $migration)->exists()) {
        return;
    }
    DB::table('migrations')->insert([
        'migration' => $migration,
        'batch' => (int) DB::table('migrations')->max('batch') + 1,
    ]);
    $log("marked {$migration} as run");
};

DB::transaction(function () use ($log, $markAsRun) {
    // Keep v2 facts that the v3 migrations drop; they are re-applied by
    // database/migrations/2026_10_22_000001_eea_v2_upgrade_fixups.php
    Schema::create('eea_v2_upgrade', function (Blueprint $table) {
        $table->string('kind');
        $table->unsignedInteger('v2_id');
        $table->unsignedInteger('component_id')->nullable();
        $table->string('name')->nullable();
        $table->timestamp('scheduled_at')->nullable();
    });
    DB::table('eea_v2_upgrade')->insertUsing(['kind', 'v2_id'],
        DB::table('subscribers')->selectRaw("'unverified_subscriber', id")->whereNull('verified_at'));
    DB::table('eea_v2_upgrade')->insertUsing(['kind', 'v2_id', 'component_id', 'name', 'scheduled_at'],
        DB::table('incidents')->selectRaw("'scheduled_incident', id, component_id, name, scheduled_at")
            ->whereNotNull('scheduled_at')->where('component_id', '>', 0));
    // v2.3 has no group visibility (every group is public); core adds the
    // column with "authenticated" as default, which hides them from the status page
    if (! Schema::hasColumn('component_groups', 'visible')) {
        DB::table('eea_v2_upgrade')->insertUsing(['kind', 'v2_id'],
            DB::table('component_groups')->selectRaw("'public_group', id"));
    }
    $log('saved '.DB::table('eea_v2_upgrade')->count().' v2 facts for the post-migration fixups');

    // users: keep id, email, password, remember_token and timestamps;
    // reshape the rest to the v3 "create_users_table" layout.
    Schema::table('users', function (Blueprint $table) {
        $table->renameColumn('username', 'name');
    });
    Schema::table('users', function (Blueprint $table) {
        $table->dropUnique('users_username_unique');
        $table->timestamp('email_verified_at')->nullable();
        // v3 keeps API tokens in api_keys; the v2 per-user key is no longer used
        $table->string('api_key')->nullable()->change();
    });
    $log('users: renamed username to name, added email_verified_at');
    $markAsRun('2014_10_12_000000_create_users_table');

    // settings: core's "update_settings_table" adds a NOT NULL json "payload"
    // column without a default, which PostgreSQL rejects when the table has
    // rows (always the case for v2). Apply the same change with the column
    // filled first; "migrate_settings" then converts the rows as upstream intends.
    if (! Schema::hasColumn('settings', 'payload')) {
        Schema::table('settings', function (Blueprint $table) {
            $table->string('group')->after('id')->default('cachet');
            $table->boolean('locked')->default(false)->after('name');
            $table->json('payload')->nullable()->after('locked');
            $table->text('value')->nullable()->change();
            $table->unique(['group', 'name']);
        });
        DB::table('settings')->orderBy('id')->each(function ($setting) {
            DB::table('settings')->where('id', $setting->id)->update(['payload' => json_encode($setting->value)]);
        });
        Schema::table('settings', function (Blueprint $table) {
            $table->json('payload')->nullable(false)->change();
        });
        $log('settings: added group, locked and payload columns');
        $markAsRun('2024_01_22_202432_update_settings_table');
    }

    // components: core's "make_component_columns_nullable" also turns the v2
    // text "description" into varchar(255), which fails (or would truncate)
    // for longer descriptions. Apply it here keeping description as text.
    // group_id is renamed to component_group_id later by core.
    Schema::table('components', function (Blueprint $table) {
        $table->text('description')->nullable()->change();
        $table->integer('status')->nullable()->change();
        $table->integer('order')->nullable()->change();
        $table->integer('group_id')->nullable()->change();
    });
    $log('components: made description, status, order and group_id nullable (description stays text)');
    $markAsRun('2023_08_18_130542_make_component_columns_nullable');

    // Queue tables hold serialized v2 jobs that v3 cannot run; v3 recreates them.
    foreach (['jobs', 'failed_jobs'] as $table) {
        if (Schema::hasTable($table)) {
            $count = DB::table($table)->count();
            Schema::drop($table);
            $log("dropped v2 table {$table} ({$count} rows)");
        }
    }
});

$log('done; "php artisan migrate" will now apply the v3 migrations');
