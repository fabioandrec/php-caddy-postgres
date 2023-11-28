#syntax=docker/dockerfile:1.4

# Versions
FROM php:8.2-fpm-alpine AS php_upstream
FROM mlocati/php-extension-installer:2 AS php_extension_installer_upstream
FROM caddy:2-alpine AS caddy_upstream
FROM node:20.9.0-alpine AS node_upstream

# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target


# Base PHP image
FROM php_upstream AS php_base

WORKDIR /var/www/html

# persistent / runtime deps
# hadolint ignore=DL3018
RUN apk add --no-cache \
        su-exec \
		fcgi \
		file \
		gettext \
		git \
        shadow \
	;

# Add a non-root user to prevent files being created with root permissions on host machine.
ARG PUID=1000
ENV PUID ${PUID}
ARG PGID=1000
ENV PGID ${PGID}

RUN set -xe; \
    groupadd -g ${PGID} sgas && \
    useradd -u ${PUID} -g sgas -m sgas && \
    usermod -p "*" sgas -s /bin/bash \
    ;

# php extensions installer: https://github.com/mlocati/docker-php-extension-installer
COPY --from=php_extension_installer_upstream --link /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=node_upstream --link /usr/local /usr/local

RUN set -eux; \
    install-php-extensions \
        @composer \
		apcu \
		intl \
		opcache \
		pdo_pgsql \
		zip \
    ;

COPY --link docker/php/conf.d/app.ini $PHP_INI_DIR/conf.d/

COPY --link docker/php/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
# RUN mkdir -p /var/run/php

COPY --link --chmod=755 docker/php/docker-healthcheck.sh /usr/local/bin/docker-healthcheck
HEALTHCHECK --start-period=1m CMD docker-healthcheck

COPY --link --chmod=755 docker/php/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]

# Dev PHP image
FROM php_base AS php_dev

ENV APP_ENV=dev XDEBUG_MODE=off
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

RUN set -eux; \
	install-php-extensions \
    	xdebug \
    ;

COPY --link docker/php/conf.d/app.dev.ini $PHP_INI_DIR/conf.d/

# Prod PHP image
FROM php_base AS php_prod

ENV APP_ENV=prod

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY --link docker/php/conf.d/app.prod.ini $PHP_INI_DIR/conf.d/

# copy sources
COPY --link . ./
RUN rm -Rf docker/

RUN set -eux; \
	mkdir -p var/cache var/log; \
	composer dump-autoload --classmap-authoritative --no-dev; \
	composer dump-env prod; \
	composer run-script --no-dev post-install-cmd; \
	chmod +x bin/console; sync;

# Base Caddy image
FROM caddy_upstream AS caddy_base

ARG TARGETARCH

WORKDIR /var/www/html

COPY --link docker/caddy/Caddyfile /etc/caddy/Caddyfile
HEALTHCHECK CMD wget --no-verbose --tries=1 --spider http://localhost:2019/metrics || exit 1

# Prod Caddy image
FROM caddy_base AS caddy_prod

COPY --from=php_prod --link /var/www/html/public public/