<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/*
 * EEA: restores Cachet v2 data that the v3 migrations do not carry over.
 * Only does something after an upgrade prepared by v2-upgrade.php
 * (which creates the eea_v2_upgrade table); a no-op on fresh installs.
 */
return new class extends Migration
{
    public function up(): void
    {
        $now = now();

        // v2 linked an incident to one component through incidents.component_id;
        // v3 reads the incident_components pivot.
        if (Schema::hasColumn('incidents', 'component_id')) {
            DB::table('incident_components')->insertUsing(
                ['incident_id', 'component_id', 'created_at', 'updated_at'],
                DB::table('incidents')
                    ->join('components', 'components.id', '=', 'incidents.component_id')
                    ->whereNotExists(fn ($query) => $query->from('incident_components')
                        ->whereColumn('incident_components.incident_id', 'incidents.id')
                        ->whereColumn('incident_components.component_id', 'incidents.component_id'))
                    ->select('incidents.id', 'incidents.component_id', 'incidents.created_at', 'incidents.updated_at')
            );
        }

        // v2 kept the banner image base64-encoded in the "app_banner" setting
        // (now app.banner); v3 expects a file on the uploads disk in theme.app_banner.
        $banner = DB::table('settings')->where('group', 'app')->where('name', 'banner')->value('payload');
        $themeBanner = DB::table('settings')->where('group', 'theme')->where('name', 'app_banner')->value('payload');
        if ($banner && json_decode($banner) && $themeBanner !== null && json_decode($themeBanner) === null) {
            $type = json_decode((string) DB::table('settings')->where('group', 'app')->where('name', 'banner_type')->value('payload'));
            $extension = match ($type) {
                'image/png' => 'png',
                'image/jpeg' => 'jpg',
                'image/webp' => 'webp',
                default => 'gif',
            };
            $path = "banner.{$extension}";
            Storage::disk((string) config('cachet.uploads.disk', 'public'))->put($path, base64_decode(json_decode($banner)));
            DB::table('settings')->where('group', 'theme')->where('name', 'app_banner')->update(['payload' => json_encode($path)]);
            DB::table('settings')->where('group', 'app')->whereIn('name', ['banner', 'banner_type'])->delete();
        }

        if (! Schema::hasTable('eea_v2_upgrade')) {
            return;
        }

        // v2 scheduled maintenance became schedules without their component.
        DB::table('eea_v2_upgrade')->where('kind', 'scheduled_incident')->get()
            ->each(function ($row) use ($now) {
                $schedule = DB::table('schedules')
                    ->where('name', $row->name)
                    ->where('scheduled_at', $row->scheduled_at)
                    ->first();
                $exists = $schedule && DB::table('schedule_components')
                    ->where('schedule_id', $schedule->id)
                    ->where('component_id', $row->component_id)
                    ->exists();
                if ($schedule && ! $exists && DB::table('components')->where('id', $row->component_id)->exists()) {
                    DB::table('schedule_components')->insert([
                        'schedule_id' => $schedule->id,
                        'component_id' => $row->component_id,
                        'component_status' => 6, // ComponentStatusEnum::under_maintenance
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]);
                }
            });

        // v2.3 component groups were public; keep them visible to guests
        DB::table('component_groups')
            ->whereIn('id', DB::table('eea_v2_upgrade')->where('kind', 'public_group')->select('v2_id'))
            ->update(['visible' => 1]); // ResourceVisibilityEnum::guest

        // core marks every subscriber verified; keep v2 unverified subscribers unverified
        DB::table('subscribers')
            ->whereIn('id', DB::table('eea_v2_upgrade')->where('kind', 'unverified_subscriber')->select('v2_id'))
            ->update(['email_verified_at' => null]);

        Schema::drop('eea_v2_upgrade');
    }

    public function down(): void
    {
        //
    }
};
