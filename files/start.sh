#! /bin/bash

set -e
#[ -z "$DEBUG" ] || set -x


D=/var/www/simplestreams
CONF=/var/www/supervisord.conf

for n in images streams/v1 ; do
    [ -d "$D/$n" ] || mkdir -p "$D/$n"
done

if [ ! -f "$D/streams/v1/index.json" ]; then
    params=(--log-file STDOUT)
    [ -z "$DEBUG" ] || params+=(--verbose)
    params+=(init)

    /usr/local/bin/lxd-image-server "${params[@]}"
fi

params=(--allow-delete --allow-overwrite --base-dir "$D")
[ -z "$DEBUG" ] || params+=(--debug)
cmd_upload="/upload-server/upload-server.py ${params[*]}"

params=(--log-file STDOUT)
[ -z "$DEBUG" ] || params+=(--verbose)
params+=(watch --skip-watch-config-non-existent)
cmd_image_server="/usr/local/bin/lxd-image-server ${params[*]}"

SUPERVISORD_LOGLEVEL=info
# [ -z "$DEBUG" ] || SUPERVISORD_LOGLEVEL=debug

cat >> "$CONF" <<EOS
[supervisord]
nodaemon=true
pidfile=/var/www/supervisord.pid
logfile=/dev/stderr
logfile_maxbytes=0
loglevel=$SUPERVISORD_LOGLEVEL

[program:nginx]
directory=/var/www/simplestreams
command=nginx -g "daemon off;"
autostart=true
autorestart=true
startretries=5
numprocs=1
startsecs=0
process_name=%(program_name)s_%(process_num)02d
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:uploader]
command=$cmd_upload
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=PYTHONUNBUFFERED="1"

[program:updater]
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
command=$cmd_image_server
environment=PYTHONUNBUFFERED="1"

EOS

#cat "$CONF"
exec supervisord -c "$CONF"

