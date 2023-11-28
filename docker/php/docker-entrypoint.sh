#!/bin/sh
set -e

if [ ! -z "$WWWUSER" ]; then
    usermod -u $WWWUSER sgas
fi

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- php-fpm "$@"
fi

if [ "$1" != 'php-fpm' ]; then
	exec su-exec $WWWUSER "$@"
else
	exec docker-php-entrypoint "$@"
fi