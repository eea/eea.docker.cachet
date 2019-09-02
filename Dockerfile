FROM cachethq/docker:2.3.15



ENV archive_url https://github.com/cachethq/Cachet/archive/v2.3.18.tar.gz
ENV cachet_ver v2.3.18

USER root
RUN rm -rf /var/www/html/* 
COPY conf/.env.docker /var/www/html/.env

COPY error/* /var/www/html/public/error/

RUN   wget ${archive_url} && \
    tar xzf ${cachet_ver}.tar.gz --strip-components=1 && \
    chown -R www-data:root /var/www/html && \
    rm -r ${cachet_ver}.tar.gz 

RUN chmod -R 777 /etc/nginx   

USER 1001
RUN  rm -rf bootstrap/cache/* && \
     sed -i 's/APP_LOG=.*/APP_LOG=errorlog/g'  /var/www/html/.env && \
     sed -i 's/APP_TIMEZONE=.*/APP_TIMEZONE=UTC/g' /var/www/html/.env && \
     php /bin/composer.phar install --no-dev -o --no-scripts && \
     rm -rf bootstrap/cache/*

COPY entrypoint.sh /sbin/entrypoint.sh
COPY conf/.env.docker /var/www/html/.env



