FROM composer:2.10.3 AS composer

FROM php:8.3.36-fpm-alpine3.24

# Cachet v3 is not tagged yet: pin the app repository to a commit.
# cachethq/core is pinned by the app's composer.lock.
ARG CACHET_REF=40bd0819ee46ee7094c336a1240a2a7a1291ccb8
ARG CACHET_ARCHIVE=https://github.com/cachethq/cachet/archive/${CACHET_REF}.tar.gz

ENV CACHET_REF=${CACHET_REF} \
    APP_DIR=/var/www/html

EXPOSE 8000
WORKDIR ${APP_DIR}

# runtime packages
RUN apk add --no-cache \
        bash \
        nginx \
        supervisor \
        icu-libs \
        libzip \
        libpq \
        libpng \
        libjpeg-turbo \
        freetype \
        tzdata

# PHP extensions needed by Laravel 13 / Filament / Cachet
RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        icu-dev \
        libzip-dev \
        postgresql-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        linux-headers; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        zip; \
    apk del --no-network .build-deps; \
    php -m

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

# application
RUN set -eux; \
    wget -qO /tmp/cachet.tar.gz "${CACHET_ARCHIVE}"; \
    tar xzf /tmp/cachet.tar.gz --strip-components=1 -C "${APP_DIR}"; \
    rm /tmp/cachet.tar.gz; \
    composer install --no-dev --no-interaction --no-progress --optimize-autoloader; \
    composer clear-cache; \
# keep the v2 table prefix (chq_) working: upstream hard-codes an empty prefix.
# Index names stay unprefixed: Cachet's migrations drop indexes by literal name,
# and the v2 (Laravel 5.2) schema never prefixed index names either.
    sed -i -e "s/'prefix' => '',/'prefix' => env('DB_PREFIX', ''),/" \
        -e "s/'prefix_indexes' => true,/'prefix_indexes' => false,/" config/database.php; \
    grep -c "env('DB_PREFIX'" config/database.php; \
    grep -c "'prefix_indexes' => false" config/database.php; \
# publish Cachet and Filament assets into public/; --force is required: it also
# replaces the outdated config/cachet.php shipped by the app with core's version
    export APP_KEY="base64:$(head -c32 /dev/urandom | base64)"; \
    php artisan vendor:publish --tag=cachet --force; \
    php artisan vendor:publish --tag=laravel-assets --force; \
    php artisan filament:assets; \
    unset APP_KEY; \
# serve uploads (status page banner, ...) from storage/app/public at /storage
    ln -s ../storage/app/public public/storage; \
    rm -f .env; \
    rm -rf bootstrap/cache/*.php storage/logs/* tests

COPY conf/php.ini /usr/local/etc/php/conf.d/zz-cachet.ini
COPY conf/settings.php ${APP_DIR}/config/settings.php
COPY conf/php-fpm-pool.conf /usr/local/etc/php-fpm.d/www.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/nginx-site.conf /etc/nginx/http.d/default.conf
COPY conf/supervisord.conf /etc/supervisord.conf
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
# Cachet v2 -> v3 database upgrade helpers
COPY scripts/v2-upgrade.php /usr/local/share/cachet/v2-upgrade.php
COPY migrations/ ${APP_DIR}/database/migrations/
COPY error ${APP_DIR}/public/error

# the image runs as uid 1001 with group root (OpenShift/Rancher style arbitrary uid)
RUN set -eux; \
    rm -f /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/www.conf.default; \
    adduser -S -D -H -u 1001 -G root -s /sbin/nologin cachet; \
    mkdir -p /var/lib/nginx/tmp /var/log/nginx /run/nginx; \
    chown -R 1001:0 ${APP_DIR} /var/lib/nginx /var/log/nginx /run/nginx /usr/local/etc/php-fpm.d; \
    chmod -R g=u ${APP_DIR}/storage ${APP_DIR}/bootstrap/cache /var/lib/nginx /var/log/nginx /run/nginx /usr/local/etc/php-fpm.d; \
    chmod +x /usr/local/bin/entrypoint.sh

USER 1001

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO /dev/null http://127.0.0.1:8000/up || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]
