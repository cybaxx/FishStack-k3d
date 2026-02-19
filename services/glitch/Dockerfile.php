FROM docker.io/node:14 AS npm

COPY ./src/public_html /public_html

RUN set -exu \
  && cd /public_html \
  && npm install

FROM docker.io/php:5.6-fpm-alpine

COPY --from=npm /public_html /var/www

RUN set -exu \
  && chown -R www-data:www-data /var/www \
  && chmod -R 755 /var/www

EXPOSE 9000

WORKDIR /var/www

CMD ["php-fpm"]
