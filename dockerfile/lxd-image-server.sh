#shellcheck shell=bash

run_lxd_image_server_install() {
    cmd_apt_min_install git patch 

    enter_run_cmd
    cat <<'EOS'
    ; echo "Configuring lxd-image-server" \
EOS
    if [ -n "$FORCE_GIT_CLONE" ]; then
        run_current_timestamp
    fi
    cat <<'EOS'
    ; git clone https://github.com/cr1st1p/lxd-image-server --branch import-metadata \
    ; sed -i -E -e 's@(packages=.*)@\1 zip_safe=False,@' lxd-image-server/setup.py \
    ; echo "Installing lxd-image-server" \
    ; cd lxd-image-server \
    ; python3 setup.py install \
    ; cd .. \
EOS
}

run_lxd_image_server_setup() {
    enter_run_cmd
    cat << 'EOS'
    ; cp lxd-image-server/resources/nginx/includes/lxd-image-server.pkg.conf /etc/nginx/lxd-image-server.conf \
    ; mkdir -p /etc/nginx/ssl \
    ; touch /etc/nginx/ssl/nginx.key \
    ; mkdir /etc/nginx/sites-enabled/ \
    ; touch /etc/nginx/sites-enabled/simplestreams.conf \
    ; mkdir /etc/lxd-image-server \
    ; mkdir -p /var/www/simplestreams \
    ; /usr/local/bin/lxd-image-server --log-file STDOUT init \
    ; chown -R nginx:nginx /var/www/simplestreams \
EOS
}

run_lxd_image_server_cleanup() {
    enter_run_cmd
    cat <<'EOS'
    ; rm -rf lxd-image-server \
EOS
    cmd_apt_purge_packages git patch
}
