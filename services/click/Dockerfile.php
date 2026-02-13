FROM docker.io/php:5.6-fpm-alpine

RUN docker-php-ext-install mysqli mysql

COPY ./wwwroot /var/www

RUN set -exu \
  && chown -R www-data:www-data /var/www \
  && chmod -R 755 /var/www

EXPOSE 9000

WORKDIR /var/www

CMD ["php-fpm"]
