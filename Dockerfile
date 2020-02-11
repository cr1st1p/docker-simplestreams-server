FROM ubuntu:bionic-20200112

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

VOLUME /var/www/simplestreams
EXPOSE 1080

COPY files/ /
SHELL ["/bin/bash", "-c"] 
RUN set -e \
    ; apt-get update -qq \
    ; DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -yqq -o Dpkg::Options::=--force-unsafe-io \
        gnupg2 apt-transport-https ca-certificates \
    ; echo "NGINX SETUP" \
    ; NGINX_GPGKEY=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 \
	; found='' \
	; for server in \
		ha.pool.sks-keyservers.net \
		hkp://keyserver.ubuntu.com:80 \
		hkp://p80.pool.sks-keyservers.net:80 \
		pgp.mit.edu \
	; do \
		echo "Fetching GPG key $NGINX_GPGKEY from $server"; \
		apt-key adv --no-tty --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$NGINX_GPGKEY" && found=yes && break; \
	done \
	; test -z "$found" && echo >&2 "error: failed to fetch GPG key $NGINX_GPGKEY" && exit 1 \
    ; echo "deb https://nginx.org/packages/mainline/ubuntu/ bionic nginx" >> /etc/apt/sources.list.d/nginx.list \
    ; apt-get update -qq \
    ; DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -yqq -o Dpkg::Options::=--force-unsafe-io \
        nginx \
    ; echo "forward request and error logs to docker log collector" \
    ; ln -sf /dev/stdout /var/log/nginx/access.log \
	; ln -sf /dev/stderr /var/log/nginx/error.log \
    ; touch /var/run/nginx.pid \
    ; sed -i -E -e 's@^\s*user\s+.*;@@' /etc/nginx/nginx.conf \
    ; chown -R nginx:nginx /var/cache/nginx /var/run/nginx.pid \
    ; DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -yqq -o Dpkg::Options::=--force-unsafe-io \
        python3 python3-setuptools python3-pip \
    ; echo "Installing 'supervisor'" \
    ; pip3 install supervisor \
    ; DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -yqq -o Dpkg::Options::=--force-unsafe-io \
        python3-bottle \
    ; mkdir -p /var/www \
    ; touch /var/www/supervisord.conf \
    ; touch /var/www/supervisord.pid \
    ; chown nginx:nginx /var/www/supervisord.* \
    ; echo "Installing debugging tools" \
    ; export DEBIAN_FRONTEND=noninteractive \
    ; apt-get install --no-install-recommends --no-install-suggests -yqq strace curl wget netcat nano \
    ; DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -yqq -o Dpkg::Options::=--force-unsafe-io \
        git patch \
    ; echo "Configuring lxd-image-server" \
    ; git clone https://github.com/cr1st1p/lxd-image-server --branch import-metadata \
    ; sed -i -E -e 's@(packages=.*)@\1 zip_safe=False,@' lxd-image-server/setup.py \
    ; echo "Installing lxd-image-server" \
    ; cd lxd-image-server \
    ; python3 setup.py install \
    ; cd .. \
    ; cp lxd-image-server/resources/nginx/includes/lxd-image-server.pkg.conf /etc/nginx/lxd-image-server.conf \
    ; mkdir -p /etc/nginx/ssl \
    ; touch /etc/nginx/ssl/nginx.key \
    ; mkdir /etc/nginx/sites-enabled/ \
    ; touch /etc/nginx/sites-enabled/simplestreams.conf \
    ; mkdir /etc/lxd-image-server \
    ; mkdir -p /var/www/simplestreams \
    ; /usr/local/bin/lxd-image-server --log-file STDOUT init \
    ; chown -R nginx:nginx /var/www/simplestreams \
    ; chmod +x /start.sh \
    ; mv /site.conf /etc/nginx/conf.d/default.conf \
    ; rm -rf lxd-image-server \
    ; DEBIAN_FRONTEND=noninteractive apt-get purge -y -o Dpkg::Options::=--force-unsafe-io \
        git patch \
    ; DEBIAN_FRONTEND=noninteractive apt-get purge -y -o Dpkg::Options::=--force-unsafe-io \
        gnupg2 apt-transport-https ca-certificates \
    ; DEBIAN_FRONTEND=noninteractive apt-get purge -y -o Dpkg::Options::=--force-unsafe-io \
        command-not-found command-not-found-data man-db manpages python3-commandnotfound python3-update-manager update-manager-core \
    ; apt-get purge -y --auto-remove \
    ; apt-get clean -q \
    ; rm -f /etc/dpkg/dpkg.cfg.d/02apt-speedup || true \
    ; rm -rf /var/lib/apt/lists/* \
    ; true

USER nginx    
CMD /start.sh
ENV DEBUG= \
    ALLOW_OVERWRITE= \
    ALLOW_DELETE=
    
