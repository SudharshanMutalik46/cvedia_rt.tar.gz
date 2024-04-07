#!/bin/bash

CWD="$(pwd)"

### WRAPPER ###################################################################

# this creates a copy of self that is executed in a subshell allowing the real
# script to be overwritten in the case a redist update happens. this works as
# long as the current wrapper code piece doesn't change, so don't change it :)

if [ -z "$IS_WRAPPED" ] ; then
    export IS_WRAPPED=1
    WFN=$(mktemp -p "$CWD" --suffix=.sh)
    #shellcheck disable=SC2068,SC2086,SC2128
    cp "$BASH_SOURCE" "$WFN" && chmod +x $WFN && $WFN $@
    RT=$?
    rm -f "$WFN" &> /dev/null
    exit $RT
fi

### REAL SELF #################################################################

#shellcheck disable=SC1091
source $(dirname $(realpath $BASH_SOURCE))/include/common.sh

if [ -z "${CRT_REGISTRY+x}" -a -f "${CRT_PATH}/.registry" ] ; then
    CRT_REGISTRY=$(cat "${CRT_PATH}/.registry")/
else
    CRT_REGISTRY=cvediaclients.azurecr.io/
fi

CREDS=${CREDS-/root/.docker/config.json}
MATCH=${MATCH-cvedia-rt}
UPDATE_DOCKER=${UPDATE_DOCKER-0}
UPDATE_REDIST=${UPDATE_REDIST-0}
DOCKER_CMD=${DOCKER_CMD-docker}
SKIP_CREDS=${SKIP_CREDS-0}
SKIP_EXTRACT=${SKIP_EXTRACT-1}
BIN_URI=${BIN_URI-https://bin.cvedia.com/}
DRY_RUN=${DRY_RUN-0}
TFN=

### ARG PARSE #################################################################

PROGNAME=$0

#shellcheck disable=SC2120
usage () {
	if [ -n "$*" ]; then
		message "usage error: $*"
	fi
	cat <<EOF
Usage: $PROGNAME [OPTIONS ...]

This script automatically update dockerized instances of CVEDIA-RT and / or redist scripts.

Options:
    -h, --help: Shows this message and exit

    -r, --registry <uri>: Overrides docker registry, default: $CRT_REGISTRY
    -c, --creds <path>: Overrides docker credentials path, default: $CREDS
    -b, --bin <uri>: Overrides binary download uri, default: $BIN_URI
    -m, --match <string>: Overrides container name match, default: $MATCH
    
    -a, --all: Update all
    --update_docker: Updates dockerized CVEDIA-RT instances
    --update_redist: Updates redist scripts 

    -e, --extract: Extract existing projets/solutions from docker image before updating.

    --skip-creds: Skip credentials check

    -D, --docker_cmd <cmd>: Overrides docker command, default: $DOCKER_CMD
    -v, --version <version>: Manually specify current redist version
    -t, --target <version>: Manually specify target redist version

    -Z, --dry_run: Do not change anything, just print the commands that would be executed

EOF
}

ARGS=$(getopt --options +h,r:,c:,Z,a,D:,b:,m:,v:,t:,e \
	--long help,registry:,creds:,update-docker,update_docker,update-redist,update_redist,dry_run,dry-run,skip_creds,skip-creds,all,docker_cmd:,docker-cmd:,extract,bin:,match:,version:,target: \
	--name "$PROGNAME" -- "$@")
GETOPT_STATUS=$?

if [ $GETOPT_STATUS -ne 0 ]; then
	error "internal error; getopt exited with status $GETOPT_STATUS"
	exit 6
fi

eval set -- "$ARGS"

if [ "$#" != 0 ] ; then
    while :; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -r|--registry) declare -x CRT_REGISTRY="$2" ; shift ;;
            -c|--creds) declare -x CREDS="$2" ; shift ;;
            -m|--match) declare -x MATCH="$2" ; shift ;;

            -a|--all) declare -x UPDATE_DOCKER=1 ; declare -x UPDATE_REDIST=1 ;;
            --update-docker|--update_docker) declare -x UPDATE_DOCKER=1 ;;
            --update-redist|--update_redist) declare -x UPDATE_REDIST=1 ;;
            -b|--bin) declare -x BIN_URI="$2" ; shift ;;
            -e|--extract) declare -x SKIP_EXTRACT=0 ;;

            -D|--docker_cmd|--docker-cmd) declare -x DOCKER_CMD="$2"; shift ;;

            --skip_creds|--skip-creds) declare -x SKIP_CREDS=1 ;;
            
            -Z|--dry_run|--dry-run) declare -x DRY_RUN=1 ;;
            -v|--version) declare -x MANUAL_VERSION="$2" ; shift ;;
            -t|--target) declare -x MANUAL_TARGET="$2" ; shift ;;

            --) shift; break ;;

            *) echo "Unknown option \"$1\" aborting"; exit 6 ;;
        esac
        shift
    done
fi

### MAIN ######################################################################

if [ "$UPDATE_DOCKER" == "0" -a "$UPDATE_REDIST" == "0" ] ; then
    usage
    log ERROR "Nothing to update, please specify --update-docker, --update-redist or --all"
    exit 1
fi

if [ "${EUID:-$(id -u)}" -ne 0 ] ; then
    log ERROR "This script must be run as root, eg: sudo $0"
    exit 1
fi

if [ "$DRY_RUN" == "1" ] ; then
    log WARN "Dry run mode enabled, no changes will be made"
fi

if [ "$UPDATE_REDIST" == "1" ] ; then
    log INFO "Updating redist scripts"
    
    if [ ! -x "$(command -v curl)" ] ; then
        log ERROR "curl is not installed, please install it and try again"
        log ERROR "try running: apt-get install curl -y"
        exit 1
    fi
    
    # find current release version

    CRELEASE=
    
    if [ -n "$MANUAL_VERSION" ] ; then
        log DEBUG "Using manually defined version: $MANUAL_VERSION"
        CRELEASE=$MANUAL_VERSION
    else
        if [ ! -f "${CRT_PATH}/.version" ] ; then
            log ERROR "Cannot find ${CRT_PATH}/.version file, please run this script from the redist directory or specify the current version using --version <version>, eg: --version 2022.6.0"
            exit 1
        fi

        #shellcheck disable=SC2002
        CRELEASE=$(cat "${CRT_PATH}/.version" | tr -cd '0-9.')
    fi

    if [ -z "$CRELEASE" ] ; then
        log ERROR "Cannot find current release version / empty / invalid version, please check ${CRT_PATH}/.version file"
        exit 1
    fi

    # find latest release version
    
    LRELEASE=
    
    if [ -n "$MANUAL_TARGET" ] ; then
        log DEBUG "Using manually defined target version: $MANUAL_TARGET"
        LRELEASE=$MANUAL_TARGET
    else
        if [ "$CRT_REGISTRY" != "docker.io/" -a -f "${CRT_PATH}/.tag" ] ; then
            #shellcheck disable=SC2002
            SUFFIX=$(cat "${CRT_PATH}/.tag" | cut -d'/' -f1)
            if [ -n "$SUFFIX" ] ; then
                log DEBUG "Using suffix: $SUFFIX"
                BIN_URI="${BIN_URI}${SUFFIX}/"
            fi
        fi

        LURI=${BIN_URI}/latest
        TFN=$(mktemp)
        curl -sfk "$LURI" -o "$TFN"
        check_exit $? "Cannot download latest version from $LURI"
        #shellcheck disable=SC2002
        LRELEASE=$(cat "$TFN" | tr -cd '0-9.')
        rm -f "$TFN" &> /dev/null

        if [ -z "$LRELEASE" ] ; then
            log ERROR "Could not get latest release from $LURI"
            exit 1
        fi
    fi

    # commit release changes
    
    log INFO "Current release: $CRELEASE"
    log INFO "Latest  release: $LRELEASE"

    if [ "$CRELEASE" == "$LRELEASE" ] ; then
        log INFO "Redist package is already up to date"
    else
        RURI=${BIN_URI}/${LRELEASE}/Linux-${LRELEASE}.tar.gz
        log INFO "Updating redist from: ${CRELEASE} to: ${LRELEASE} using: ${RURI}..."

        if [ "$DRY_RUN" == "0" ] ; then
            TFN=$(mktemp --suffix=.tar.gz)
            curl -sfk "$RURI" -o "$TFN"
            check_exit $? "Cannot download redist package from $RURI"
            tar -xzvf "$TFN" -C "${CWD}/"
            check_exit $? "Failed to extract redist package to $CWD"
            rm -f "$TFN" &> /dev/null
            log INFO "Updated redist from: ${CRELEASE} to: ${LRELEASE}, please run this update script again to update the docker instances."
            exit 0
        else
            log WARN "Dry run enabled, skipping update ${CRELEASE} to ${LRELEASE}"
        fi
    fi
fi

if [ "$UPDATE_DOCKER" == "1" ] ; then
    log INFO "Updating dockerized CVEDIA-RT instances..."
    
    #shellcheck disable=SC2086
    if [ ! -x "$(command -v $DOCKER_CMD)" ] ; then
        log ERROR "Docker command: $DOCKER_CMD not found, please install it and try again"
        exit 1
    fi

    if [ "$SKIP_CREDS" == "0" -a -n "$CRT_REGISTRY" -a "$(echo $CRT_REGISTRY | grep -c docker.io)" == "0" -a ! -f "$CREDS" ] ; then
        log ERROR "No saved credentials for $CRT_REGISTRY found at: $CREDS"
        log ERROR "You can set path to credentials using CREDS environment variable"
        exit 1
    fi

    if [ -f "$CREDS" ] ; then
        DOCKER_PARAMS="$DOCKER_PARAMS -v ${CREDS}:/config.json:ro"
    fi

    log INFO "Searching for running containers matching: $MATCH"
    K=0
    PRE_DIG=
    POST_DIG=
    #shellcheck disable=SC2046,SC2128
    PFOLDER=$(dirname $(realpath "$BASH_SOURCE"))/solutions
    HAS_UPDATED=0

    # HACK: hold nvidia driver busy to avoid driver deallocation on gcp
    if [ "$DRY_RUN" == "0" -a -n "$(command -v nvidia-smi)" ] ; then
        nvidia-smi -l &> /dev/null &
        NVIDIA_SMI_PID=$!
    fi

    #shellcheck disable=SC2086
    for c in $($DOCKER_CMD container ls -f name=^/${MATCH} -a --format '{{.ID}},{{.Names}},{{.Image}}'); do
        CID=$(echo $c | cut -d',' -f1)
        NAM=$(echo $c | cut -d',' -f2)
        IMG=$(echo $c | cut -d',' -f3)
        
        if [ -z "$PRE_DIG" ] ; then
            PRE_DIG=$($DOCKER_CMD inspect $IMG --format '{{.RepoDigests}}')
        fi
        
        if [ "$DRY_RUN" == "0" ] ; then
            log INFO "Pulling watchtower..."
            docker pull containrrr/watchtower
            check_exit $? "Failed to pull containrrr/watchtower"
            
            log INFO "Updating container: ${CID} ${NAM}..."
            #shellcheck disable=SC2086
            $DOCKER_CMD run --rm $DOCKER_PARAMS -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower --run-once ${NAM} --debug
            check_exit $? "Failed to update: ${CID} ${NAM}, aborting"

            if [ -z "$POST_DIG" ] ; then
                POST_DIG=$($DOCKER_CMD inspect $IMG --format '{{.RepoDigests}}')
            fi

            if [ "$SKIP_EXTRACT" == "0" -a -d "$PFOLDER" -a "$HAS_UPDATED" == "0" ] ; then
                log INFO "Updating extracted projects..."
                ./run.sh -e
                HAS_UPDATED=1
                $DOCKER_CMD container restart ${NAM}
            fi
        else
            log WARN "Dry run enabled, skipping update of container: ${CID} ${NAM} img: ${IMG}"
        fi

        K=$((K+1))
    done

    if [ "$DRY_RUN" == "0" ] ; then
        if [ -n "$NVIDIA_SMI_PID" ] ; then
            kill -9 "$NVIDIA_SMI_PID" &> /dev/null
        fi

        if [ "$K" == "0" ] ; then
            log ERROR "No running containers matching criteria: ${MATCH} found."
            log ERROR "You can set a different matching criteria using MATCH environment variable"
            exit 1
        fi
        
        log DEBUG "Previous digest: $PRE_DIG"
        log DEBUG "Current digest:  $POST_DIG"

        if [ "$PRE_DIG" == "$POST_DIG" ] ; then
            log INFO "No update needed."
        else
            log INFO "Updated $K containers."
        fi
    else
        log WARN "Dry run enabled, would've updated: $K containers."
    fi
else
    log WARN "Skipping docker deployment updates."
fi

log INFO "Completed, ${SECONDS}s elapsed."
exit 0
