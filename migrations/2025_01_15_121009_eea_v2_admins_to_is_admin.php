<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/*
 * EEA: runs right after cachethq/core's "add_admin_flag_to_users_table",
 * which adds is_admin = false for every user. Cachet v2 marked admins with
 * level = 1; keep them admins in v3.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('users', 'level')) {
            return;
        }

        DB::table('users')->where('level', 1)->update(['is_admin' => true]);
    }

    public function down(): void
    {
        //
    }
};
