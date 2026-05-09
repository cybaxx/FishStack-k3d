ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-bookworm

# SMF required PHP extensions
RUN apt-get update && apt-get install -y \
    libjpeg-dev \
    libpng-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    libmagickwand-dev \
    unzip \
    curl \
    ca-certificates \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) \
    mysqli \
    pdo_mysql \
    mbstring \
    gd \
    zip \
    iconv \
    intl \
    exif \
    curl \
  && pecl install imagick-3.8.0 \
  && docker-php-ext-enable imagick \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/forum

# Copy SMF files from local src/ directory (pre-extracted SMF 2.1.6)
# src/ is gitignored — populate with: cp -r <forum-repo>/projects/smf-docker/app src
COPY src/ .

RUN set -eu; \
  chown -R www-data:www-data .; \
  find . -type d -exec chmod 755 {} \; ; \
  find . -type f -exec chmod 644 {} \;

# Copy fish avatar builder assets (WFIE item images, bodies, equipment, coins)
COPY fish/ /var/www/forum/fish/

# Copy env-driven Settings.php
COPY config/Settings.php /var/www/forum/Settings.php
COPY config/Settings.php /var/www/forum/Settings_bak.php

# Copy PHP overrides
COPY config/php-overrides.ini /usr/local/etc/php/conf.d/99-forum-overrides.ini

# Copy k8s entrypoint
COPY config/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]
