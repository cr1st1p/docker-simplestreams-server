#!/usr/bin/env bash

# I hate how Dockerfile always correlates image layers with *each* RUN command. 
# it creates this big pile of inline shell script that looks like hell...
#


# run_* functions are to be run with Dockerfile 'RUN'. For the moment, just a nomenclature, not
# a requirement
set -e

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for n in main.sh apt.sh nginx.sh python.sh debugging.sh supervisor.sh; do
    # shellcheck disable=SC1090
    source "${SCRIPT_PATH}/dockerfile-lib/$n"
done
for n in "lxd-image-server.sh"; do
    # shellcheck disable=SC1090
    source "${SCRIPT_PATH}/dockerfile/$n"
done



DEV_MODE=
FORCE_GIT_CLONE=



# ==========
run_supervisor_setup() {
    enter_run_cmd
    # we precreate the configuration file in here and change
    # ownership so that during start.sh we can put the appropriate
    # settings
    cat <<'EOS'
    ; mkdir -p /var/www \
    ; touch /var/www/supervisord.conf \
    ; touch /var/www/supervisord.pid \
    ; chown nginx:nginx /var/www/supervisord.* \
EOS
}


# =======================



# =========
run_upload_server_install_requirements() {
    cmd_apt_min_install python3-bottle
}

# =========
run_cleanup() {
    enter_run_cmd

    run_lxd_image_server_cleanup
    run_apt_remove_initial_packages
    run_apt_cleanups
}



# =======
copy_files() {
    exit_run_cmd

    cat << 'EOS'
COPY files/ /
EOS
}


run_fix_files() {
    enter_run_cmd

    cat << 'EOS'
    ; chmod +x /start.sh \
    ; mv /site.conf /etc/nginx/conf.d/default.conf \
EOS
}


start_stuff() {
    exit_run_cmd


    GEN_FROM "ubuntu:bionic-20200112"

    cat <<'EOS'

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

VOLUME /var/www/simplestreams
EXPOSE 1080

EOS

}


end_stuff() {
    exit_run_cmd

    cat <<'EOS'
USER nginx    
CMD /start.sh
ENV DEBUG= \
    ALLOW_OVERWRITE= \
    ALLOW_DELETE=
    
EOS
}


# ==== command line parsing
checkArg () {
    if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
        echo "Expected argument for option: $1. None received"
        exit 1
    fi
}

arguments=()
while [[ $# -gt 0 ]]
do
    # split --x=y to have them separated
    [[ $1 == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"

    case "$1" in
        --dev)
            DEV_MODE=1
            shift
            ;;
        --force-git-clone)
            FORCE_GIT_CLONE=1
            shift
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        -*) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *) # preserve positional arguments
            arguments+=("$1")
            shift
            ;;
    esac    
done

# ==== and now, generate output:

start_stuff

[ -z "$DEV_MODE" ] && copy_files


run_apt_initial_minimal_installs

run_nginx_add_repo
run_supervisor_add_repo
# here: add other repos if needed
run_apt_update # call it only once

run_nginx_install
run_nginx_as_nginx_user

run_python3_install
run_supervisor_install
run_upload_server_install_requirements

run_supervisor_setup

# you should normally comment this:
run_debugging_tool_install

run_lxd_image_server_install

run_lxd_image_server_setup

[ -n "$DEV_MODE" ] && copy_files

run_fix_files

[ -z "$DEV_MODE" ] && run_cleanup

end_stuff
