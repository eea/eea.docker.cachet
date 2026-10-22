#!/bin/bash
set -o errexit -o nounset -o pipefail

[ "${DEBUG:-false}" == true ] && set -x

cd "${APP_DIR:-/var/www/html}"

# Map the variable names used by the v2 image / Helm chart to Laravel's names,
# so existing deployments keep working. New names win when both are set.
map_env() {
  local new="$1" old="$2"
  if [[ -z "${!new:-}" && -n "${!old:-}" ]]; then
    export "${new}=${!old}"
  fi
}

configure() {
  map_env DB_CONNECTION DB_DRIVER
  map_env MAIL_MAILER MAIL_DRIVER
  map_env MAIL_FROM_ADDRESS MAIL_ADDRESS
  map_env MAIL_FROM_NAME MAIL_NAME
  map_env LOG_CHANNEL APP_LOG
  map_env APP_TIMEZONE TZ
  map_env CACHE_STORE CACHE_DRIVER
  map_env QUEUE_CONNECTION QUEUE_DRIVER
  map_env CACHET_TRUSTED_PROXIES TRUSTED_PROXIES

  # v2 defaults that no longer exist in v3
  [[ "${CACHE_STORE:-}" == apc ]] && unset CACHE_STORE
  [[ "${SESSION_DRIVER:-}" == apc ]] && unset SESSION_DRIVER
  [[ "${MAIL_ENCRYPTION:-}" == "" ]] && unset MAIL_ENCRYPTION

  export APP_ENV="${APP_ENV:-production}"
  export APP_DEBUG="${APP_DEBUG:-false}"
  export APP_URL="${APP_URL:-http://localhost}"
  export LOG_CHANNEL="${LOG_CHANNEL:-stderr}"
  export DB_CONNECTION="${DB_CONNECTION:-pgsql}"
  export DB_HOST="${DB_HOST:-postgres}"
  export DB_PREFIX="${DB_PREFIX:-}"
  export CACHE_STORE="${CACHE_STORE:-database}"
  export SESSION_DRIVER="${SESSION_DRIVER:-database}"
  export QUEUE_CONNECTION="${QUEUE_CONNECTION:-database}"
  export CACHET_BEACON="${CACHET_BEACON:-false}"
  # laravel/nightwatch is installed upstream and enabled by default; without an
  # agent it instruments every request and times out reaching 127.0.0.1:2407
  export NIGHTWATCH_ENABLED="${NIGHTWATCH_ENABLED:-false}"
  export CACHET_DOCKER=true
  # TLS is terminated by the ingress in front of the container
  export CACHET_TRUSTED_PROXIES="${CACHET_TRUSTED_PROXIES:-*}"

  case "${DB_CONNECTION}" in
    pgsql) export DB_PORT="${DB_PORT:-5432}" ;;
    mysql | mariadb) export DB_PORT="${DB_PORT:-3306}" ;;
  esac

  # read by php-fpm-pool.conf and supervisord.conf
  export PHP_MAX_CHILDREN="${PHP_MAX_CHILDREN:-5}"
  export PHP_MAX_EXECUTION_TIME="${PHP_MAX_EXECUTION_TIME:-60}"
  export TIMEOUT="${TIMEOUT:-180}"

  if [[ -z "${APP_KEY:-}" || "${APP_KEY}" == "null" ]]; then
    echo "ERROR: APP_KEY is not set. Generate one with:" >&2
    echo "  docker run --rm --entrypoint php <image> artisan key:generate --show" >&2
    echo "When upgrading from Cachet v2, reuse the v2 APP_KEY." >&2
    exit 1
  fi
}

wait_for_database() {
  [[ "${DB_CONNECTION}" == sqlite ]] && return 0
  echo "Waiting for database ${DB_HOST}:${DB_PORT} ..."
  local tries=60
  until php -r '
      $dsn = sprintf("%s:host=%s;port=%s;dbname=%s",
          getenv("DB_CONNECTION") === "pgsql" ? "pgsql" : "mysql",
          getenv("DB_HOST"), getenv("DB_PORT"), getenv("DB_DATABASE"));
      new PDO($dsn, getenv("DB_USERNAME"), getenv("DB_PASSWORD"));' >/dev/null 2>&1; do
    tries=$((tries - 1))
    if [[ "${tries}" -le 0 ]]; then
      echo "Could not connect to the database. Aborting." >&2
      exit 1
    fi
    sleep 2
  done
}

migrate() {
  if [[ "${RUN_MIGRATIONS:-true}" == true ]]; then
    # the settings cache lives in the database cache table, which does not
    # exist yet on a new database: keep it off until the migrations ran.
    # v2-upgrade.php is a no-op unless the database has the Cachet v2 schema.
    SETTINGS_CACHE_ENABLED=false CACHET_SETTINGS_CACHE=false php /usr/local/share/cachet/v2-upgrade.php
    SETTINGS_CACHE_ENABLED=false CACHET_SETTINGS_CACHE=false php artisan migrate --force --no-interaction
  fi
}

configure

if [[ "${1:-}" == supervisord ]]; then
  wait_for_database
  migrate
  php artisan optimize
  echo "Starting Cachet ${CACHET_REF:-} ..."
fi

exec "$@"
