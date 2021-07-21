FROM cachethq/docker:2.3.18


USER root

COPY error /var/www/html/public/error
RUN  chown -R www-data:root /var/www/html

#set timeout to 2 minutes
RUN sed -i 's/php artisan queue:work/timeout 120 php artisan queue:work/'  /etc/supervisor/supervisord.conf

USER 1001

COPY entrypoint.sh /sbin/entrypoint.sh
COPY conf/.env.docker /var/www/html/.env
COPY conf/nginx-site.conf /etc/nginx/conf.d/default.conf


