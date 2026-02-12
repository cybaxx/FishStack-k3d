# Note: This comment was in the previous dockerfile
# Note: Not 100% sure why
#
# Small note, make sure to create upload/thumbs prior to running this! 

#
# runtime container
FROM docker.io/debian:bookworm-slim

# install PHP 8.2 (Debian bookworm default), extensions, and Node.js
RUN set -exu \
  && DEBIAN_FRONTEND=noninteractive apt-get -yq update \
  && DEBIAN_FRONTEND=noninteractive apt-get -yq install \
    php \
    php-fpm \
    php-mysqli \
    php-mysql \
    php-exif \
    php-gd \
    nodejs \
    npm \
  && DEBIAN_FRONTEND=noninteractive apt-get -yq clean

# create a builder user
RUN set -exu \
  && addgroup --gid 1101 builder \
  && adduser \
      --uid 1101 \
      --ingroup builder \
      --shell /sbin/nologin \
      --disabled-password \
      builder

# copy in sources
COPY ./wwwroot /var/www

# make sure our user owns the wwwroot
RUN set -exu \
  && chown -R builder:builder /var/www

# switch to our nonroot user
USER builder

# run npm install
WORKDIR /var/www/src
RUN set -exu \
  && cd /var/www/src \
  && npm install

# back to root
USER root

WORKDIR /var/www

RUN set -exu \
  && chown -R www-data:www-data /var/www

# Expose port 9000 and start php-fpm server
EXPOSE 9000
CMD ["php-fpm8.2", "--nodaemonize", "--force-stderr"]
