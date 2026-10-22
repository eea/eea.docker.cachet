# Cachet Docker Image

Docker image for [Cachet](https://github.com/cachethq/cachet) v3, the open source status page system.

Cachet v3 is not tagged upstream yet: the image pins the `cachethq/cachet` commit in the `CACHET_REF` build argument, and `cachethq/core` through its `composer.lock`.

The image runs nginx, php-fpm (PHP 8.3), the queue worker and the scheduler under supervisord, as uid 1001 (group root), on port 8000. Logs go to `stdout`/`stderr`.


# Quickstart

    git clone https://github.com/eea/eea.docker.cachet
    cd eea.docker.cachet
    APP_KEY="base64:$(head -c32 /dev/urandom | base64)" docker compose up --build

Then create the first user and open http://localhost:8000/dashboard

    docker compose exec cachet php artisan cachet:make:user admin@example.org --admin=1 --name=Admin

`eeacms/cachet` is available on [Docker Hub](https://hub.docker.com/r/eeacms/cachet/tags/).


# Configuration

Cachet is a Laravel application and is configured with environment variables, e.g.:

| Variable | Default | Notes |
|---|---|---|
| `APP_KEY` | - | Required. When upgrading from v2, reuse the v2 key |
| `APP_URL` | `http://localhost` | Public URL |
| `DB_CONNECTION` | `pgsql` | Also accepted as `DB_DRIVER` (v2 name) |
| `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | `postgres`, `5432` | |
| `DB_PREFIX` | empty | `chq_` for databases created by the v2 image |
| `MAIL_MAILER`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` | | v2 names `MAIL_DRIVER`, `MAIL_ADDRESS`, `MAIL_NAME` are accepted |
| `APP_TIMEZONE` | UTC | Taken from `TZ` when not set |
| `LOG_CHANNEL` | `stderr` | |
| `CACHET_TRUSTED_PROXIES` | `*` | TLS is expected to be terminated in front of the container |
| `CACHE_STORE`, `SESSION_DRIVER`, `QUEUE_CONNECTION` | `database` | |
| `PHP_MAX_CHILDREN` | `5` | php-fpm workers |
| `PHP_MAX_EXECUTION_TIME` | `60` | seconds |
| `TIMEOUT` | `180` | php-fpm request timeout and queue worker restart interval, seconds |
| `RUN_MIGRATIONS` | `true` | Run database migrations at startup |
| `DEBUG` | `false` | Trace the entrypoint script |

Uploaded files (e.g. the status page banner) are stored in `/var/www/html/storage/app/public`: mount a volume there.

Anonymous visitors of the public status pages get a copy cached by nginx for 10 seconds; logged in users always see the live page.

The health check endpoint is `/up`.


# Upgrading from Cachet v2.3 (`eeacms/cachet:2.3-x`)

The image upgrades a Cachet v2.3 database in place the first time it starts: `scripts/v2-upgrade.php` prepares the v2 schema, then the Cachet v3 migrations and the EEA migrations in `migrations/` convert the data. Upstream does not provide a complete v2 to v3 path yet; the EEA scripts keep:

- the `chq_` table prefix (set `DB_PREFIX=chq_`) and the v2 `APP_KEY`
- users and passwords, and v2 admins as v3 admins
- incident and scheduled maintenance links to components
- v2.3 component groups visible on the public status page
- component descriptions longer than 255 characters
- unverified subscribers (not marked as verified)
- the status page banner, converted to `banner.<ext>` in the uploads volume

Procedure (PostgreSQL 9.6 to 17):

1. Stop the v2 application and dump the database:

       pg_dump -h <v2 db host> -U postgres -d cachet > cachet-v2.sql

2. Create an empty database in PostgreSQL 17 (e.g. `eeacms/postgres:17s`) owned by the application user, and restore the dump **as the application user**, so that it owns every table (the migrations alter them). Leave out the PostgreSQL 9.6 specific, ownership and grant statements:

       grep -vE "^SET default_with_oids|^(CREATE|COMMENT ON) EXTENSION |^ALTER .* OWNER TO |^(GRANT|REVOKE) " cachet-v2.sql \
         | psql -h <new db host> -U cachet -d cachet -v ON_ERROR_STOP=1

3. Start this image with the same `APP_KEY` and `DB_PREFIX=chq_`. The log shows `[v2-upgrade]` lines followed by the migrations; the next starts log `no Cachet v2 schema found, nothing to do`.

The v2 database is left untouched, so it remains the fallback.

Known differences after the upgrade:

- incident pages use UUIDs (`/incidents/<uuid>`); old `/incidents/<id>` links do not work
- API clients must use `/api` (not `/api/v1`) and an API key created in Dashboard → API Keys, sent as `Authorization: Bearer <key>`; use `eeacms/cachet-monitor:3` for cachet-monitor
- the first start logs about ten `SettingAlreadyExists` errors from Cachet's default settings migration; they are expected


# Debugging

* Cachet, supervisord, nginx and php-fpm log to `stdout` and `stderr`.
* Set `DEBUG=true` to trace the container entrypoint script.
