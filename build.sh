#!/usr/bin/env bash

set -e

TAG=0.1
REPO_DIR=cristi
NAME=simplestreams-server
export DOCKER_BUILDKIT=1

DEV_MODE=
FORCE_GIT_CLONE=
REMOTE_REPO= 
DOCKER_NO_CACHE=


# command line parsing:
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
        --remote-repo)
            checkArg "$1" "$2"
            REMOTE_REPO="$2"
            shift 2;
            ;;
        --no-cache)
            DOCKER_NO_CACHE=1
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

params=()
[ -n "$DEV_MODE" ] && params+=("--dev")
[ -n "$FORCE_GIT_CLONE" ] && params+=("--force-git-clone")
./dockerfile-gen.sh "${params[@]}"  > Dockerfile


params=(-t "$REPO_DIR/$NAME:$TAG")
[ -n "$DOCKER_NO_CACHE" ] && params+=("--no-cache")
[ -n "$DOCKER_BUILDKIT" ] && params+=(--progress plain)
params+=(".")



docker build "${params[@]}"

if [ -z "$REMOTE_REPO" ]; then
    echo "After local build, at this point we need to know the remote to push to. Use --remote-repo REMOTE_REPO"
    exit 1
fi

docker tag "$REPO_DIR/$NAME:$TAG" "$REMOTE_REPO/$REPO_DIR/$NAME:$TAG" 
docker push "$REMOTE_REPO/$REPO_DIR/$NAME:$TAG" 

