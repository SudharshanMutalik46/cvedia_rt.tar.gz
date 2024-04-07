#!/bin/sh

# WARNING: Changes in this script must be POSIX

BENCHMARK_VERSION=2022.8.29

rand_str() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo ''    
}

log () {
    if [ "$NO_COLOR" = "1" ] ; then
        ERROR=
        INFO=
        WARN=
        TRACE=
        DEBUG=
        SQL=
        C_N=
    else
        ERROR='\033[1;31m'
        INFO='\033[1;32m'
        WARN='\033[1;33m'
        TRACE='\033[1;35m'
        DEBUG='\033[1;36m'
        SQL='\033[1;34m'
        C_N='\033[0m'
    fi
    level=INFO
    
    if [ -n "$1" ] ; then
        level=$1
        IN=$2 $3 $4 $5 $6 $7 $8 $9
        # IN=
        # i=1
        # while [ -n "${[$i]}" ] ; do
        #     IN="$IN ${[$i]}"
        #     i=$((i + 1))
        # done
    else
        read -r IN
    fi
    
    lvl=$INFO
    eval lvl=\$$level
    printf "${C_N}${lvl}$(date +%Y-%m-%d\ %H:%M:%S) $HOSTNAME $level [$$] $IN${C_N}\n"
}

check_exit () {
    RT=$1
    ERROR_MESSAGE=$2 $3 $4 $5 $6 $7 $8 $9
    if [ "$RT" -ne "0" ]; then
        log WARN "-- Exit code: $RT"
        if [ -n "$ERROR_MESSAGE" ] ; then
            ERROR_MESSAGE="- $ERROR_MESSAGE"
        fi
        log ERROR "Error, aborting $ERROR_MESSAGE"
        if [ -n "$PID" ]; then
            kill $PID
        fi
        exit 1
    fi
}

CWD=$(pwd)
PROGNAME=$0

#shellcheck disable=SC2120
usage () {
	if [ -n "$*" ]; then
		message "usage error: $*"
	fi
	cat <<EOF
Usage: $PROGNAME [OPTIONS ...] [[-- DOCKER PARAMS ...] [-- RUNTIME PARAMS ...]]

This script runs benchmarks of models and backends then creates a output json report.

Options:
    -h, --help: Shows this message and exit
    
    -b, --backends <backend1,backend2,backendN>: List one or more backend to be benchmaked separated by commas.
                                                 If not specified, all backends will be benchmarked.
    
    -u, --uri <uri1,uri2,urlN>: Define one or more specific model forge uris to benchmark.
                                If not specified, all compatible uris will be benchmarked.
    
    -w, --workspace <path>: Defines a workspace path
    
    -k, --keep: Keep temp files
    
    -v, --version: Prints version and exit
EOF
}

ARGS=$(getopt --options +h,b:,w:,k,v \
	--long help,backends:,workspace:,keep,version \
	--name "$PROGNAME" -- "$@")
GETOPT_STATUS=$?

if [ $GETOPT_STATUS -ne 0 ]; then
	error "internal error; getopt exited with status $GETOPT_STATUS"
	exit 6
fi

eval set -- "$ARGS"

DOCKER_PARAMS=
RUNTIME_PARAMS=

if [ "$#" != 0 ] ; then
    while :; do
        case "$1" in
            -h|--help) usage; exit 0 ;;

            -b|--backends) BENCHMARK_DEVICES="$2"; shift ;;
            -w|--workspace) WORKSPACE_ROOT="$2"; shift ;;
            -k|--keep) KEEP_TEMP=1 ;;
            -u|--uri) BENCHMARK_URIS="$2"; shift ;;

            -v|--version)
                log INFO "Benchmark version v$BENCHMARK_VERSION"
                exit 0 ;;
            
            # append rest of params after -- to DOCKER_PARAMS
            # if there's another -- break, append to RUNTIME_PARAMS
            --)
                shift
                X=0
                
                while [ $# -gt 0 ]; do
                    if [ "$X" -eq "0" ] ; then
                        if [ "$1" = "--" ] ; then
                            X=1
                            shift
                            continue
                        fi
                        DOCKER_PARAMS="$DOCKER_PARAMS $1"
                    else
                        RUNTIME_PARAMS="$RUNTIME_PARAMS $1"
                    fi
                    shift
                done
                
                break ;;

            *) echo "Unknown option \"$1\" aborting"; exit 6 ;;
        esac
        shift
    done
fi

NO_COLOR=${NO_COLOR:-0}
HOSTNAME="${HOSTNAME:-$(hostname)}"
ARCH=${ARCH-$(uname -p)}

BENCHMARK_FLAG=${BENCHMARK_FLAG-0}
CVEDIA_RT_BIN=${CVEDIA_RT_BIN-${1-/opt/cvedia-rt/}}
BENCHMARK_PATH=${BENCHMARK_PATH-${CWD}/benchmarks}
BENCHMARK_DURATION=${BENCHMARK_DURATION-60}
WORKSPACE_ROOT=${WORKSPACE_ROOT-/mnt/mmc/workspace}
DRY_RUN=${DRY_RUN-0}
KEEP_TEMP=${KEEP_TEMP-0}
SKIP_TV_SETUP=${SKIP_TV_SETUP-0}

# static overrides
RUN_UI=0
HEADLESS=1
SKIP_AUTOMOUNT=1
SKIP_CAMERA=1

TV_PIDS=

if [ "$BENCHMARK_FLAG" -eq "0" -a ! -x "$(command -v docker)" ] ; then
    log DEBUG "-- Docker command not found, assuming this is a local install / embedded device"
    BENCHMARK_FLAG=1
fi

if [ "$BENCHMARK_FLAG" -eq "1" ] ; then # within docker / local
    if [ ! -d "${CVEDIA_RT_BIN}" ] ; then
        log ERROR "-- Path: ${CVEDIA_RT_BIN} not found, you can define a custom path as the first argument of this script or on env CVEDIA_RT_BIN."
        exit 1
    fi

    WORKSPACE_PATH=${WORKSPACE_PATH-"${WORKSPACE_ROOT}/benchmark_$(rand_str)"}
    rm -fr ${WORKSPACE_PATH} >/dev/null 2>&1
    mkdir ${BENCHMARK_PATH} ${WORKSPACE_PATH} -p >/dev/null 2>&1
    
    log INFO "-- Running benchmarks using: ${CVEDIA_RT_BIN} workspace: ${WORKSPACE_PATH}"
    log DEBUG "-- Creating workspace..."
    
    cp -a "$(realpath $CVEDIA_RT_BIN)" "${WORKSPACE_PATH}/bin"
    check_exit $? "Error copying to workspace ${WORKSPACE_PATH}"
    cd "${WORKSPACE_PATH}/bin"

    if [ ! -f "listnndevices" -o ! -f "modelforge" -o ! -f "benchmark" ] ; then
        log ERROR "-- listnndevices, modelforge and / or benchmark binaries not found at ${WORKSPACE_PATH}/bin, aborting"
        exit 1
    fi

    rm -fr cvediart.key assets/models >/dev/null 2>&1
    chmod +x listnndevices modelforge benchmark >/dev/null 2>&1

    export LD_LIBRARY_PATH=/opt/lib:${WORKSPACE_PATH}/bin:/usr/local/cuda/lib64:$LD_LIBRARY_PATH
    
    if [ -x "$(command -v ldconfig)" ] ; then
        ldconfig -v >/dev/null 2>&1
    fi
    
    if [ -x "$(command -v nvidia-smi)" ] ; then
        nvidia-smi
    fi
    
    if [ "$SKIP_TV_SETUP" -eq "0" ] ; then
        for i in vana_service tv_3a_service;do
            p=$(pgrep vana_service)
            if [ -n "$p" ] ; then
                TV_PIDS="$p $TV_PIDS"
                kill -STOP $p >/dev/null 2>&1
            fi
        done
    fi
    
    ./listnndevices -b | grep -vi onnx > "${WORKSPACE_PATH}/avail_devices"
    check_exit $? "Error invoking listnndevices"
    log DEBUG "-- Available devices: $(cat ${WORKSPACE_PATH}/avail_devices)"
    
    if [ -z "$BENCHMARK_DEVICES" ] ; then
        lcmd="cat ${WORKSPACE_PATH}/avail_devices"
    else
        lcmd="echo $(echo ${BENCHMARK_DEVICES} | tr ',' ' ')"
    fi
    
    ERR=0
    log DEBUG "-- lcmd: $lcmd"
    
    for d in $($lcmd); do
        if [ "$(cat ${WORKSPACE_PATH}/avail_devices | grep -c $d)" -eq "0" ] ; then
            log WARN "-- Requested device: $d not in listnndevices list, benchmark might fail."
        fi

        if [ -z "$BENCHMARK_URIS" ] ; then
            ucmd="./modelforge -b -u ${d}://"
        else
            ucmd="echo $(echo ${BENCHMARK_URIS} | tr ',' ' ')"
        fi
        
        LOG_FN="bench_log_$(rand_str).log"
        rm -f $LOG_FN >/dev/null 2>&1
        touch $LOG_FN >/dev/null 2>&1

        log DEBUG "-- ucmd: $ucmd"
        log INFO "-- Querying models for device: ${d}..."
        log DEBUG "-- Temp log file: $LOG_FN"

        for m in $($ucmd); do
            log INFO "-- Running benchmark for: ${m}..."
            
            OFN=${BENCHMARK_PATH}/$(echo $m | tr ':/' '__')${BENCHMARK_SUFFIX}.json
            
            cmd="./benchmark -v -u $m -i 1 -d ${BENCHMARK_DURATION} -j $OFN $RUNTIME_PARAMS"
            log DEBUG "-- Running: $cmd"
            
            if [ "$DRY_RUN" -eq "0" ] ; then
                $cmd 2>&1 | tee $LOG_FN
                RT=$?
                if [ "$RT" -eq "1" ] ; then
                    {
                        echo "[$ERR] Exit code: $RT when running: $cmd"
                        cat $LOG_FN
                        echo "-------------------------------------------------------------------------------"
                    } >> ${BENCHMARK_PATH}/error.log
                    ERR=$((ERR + 1))
                fi

                rm -f $LOG_FN
            else
                log INFO "-- DRY_RUN enabled, skipping"
            fi
        done
    done

    if [ -n "$TV_PIDS" ] ; then
        kill -CONT $TV_PIDS >/dev/null 2>&1
    fi

    if [ "$KEEP_TEMP" -eq "0" ] ; then
        cd ${CWD} && rm -fr $WORKSPACE_PATH >/dev/null 2>&1
    else
        log INFO "-- KEEP_TEMP enabled: leaving ${WORKSPACE_PATH}"
    fi
else # outside docker - NOT POSIX
    log DEBUG "-- Found docker binary"
    FOREGROUND=1
    TMPFN=$(mktemp)
    export RUN_UI=0
    
    ${CWD}/include/get_docker_params.sh $TMPFN
    check_exit $? "Unable to get docker params"
    . $TMPFN
    rm -f "$TMPFN"
    mkdir ${BENCHMARK_PATH} -p >/dev/null 2>&1
    log INFO "-- Saving benchmark outputs to: ${BENCHMARK_PATH}"
    cmd="$DOCKER_CMD run -e BENCHMARK_PATH=/outputs \
-e KEEP_TEMP=$KEEP_TEMP -e BENCHMARK_SUFFIX=$BENCHMARK_SUFFIX -e WORKSPACE_ROOT=$WORKSPACE_ROOT \
-e DRY_RUN=$DRY_RUN -e BENCHMARK_DEVICES=$BENCHMARK_DEVICES -e BENCHMARK_DURATION=$BENCHMARK_DURATION \
-e BENCHMARK_FLAG=1 \
--entrypoint /opt/benchmark/benchmark.sh \
-v ${BENCHMARK_PATH}:/outputs -v ${CWD}/benchmark.sh:/opt/benchmark/benchmark.sh:ro \
-v ${CWD}/include:/opt/benchmark/include:ro \
$DOCKER_MNT $DOCKER_PARAMS \
$TAG /opt/cvedia-rt/"

    log INFO "-- Running: $cmd"
    if [ "$DRY_RUN" -eq "1" ] ; then
        log WARN "-- Dry run enabled, exiting"    
        exit 0
    fi

    $cmd
    RT=$?
    if [ "$RT" -eq "0" ] ; then
        log INFO "-- Benchmarks completed"
    else
        log ERROR "-- Benchmark exit code: $RT"
    fi
fi
