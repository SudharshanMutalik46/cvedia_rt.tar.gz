#!/bin/bash
#shellcheck disable=SC2166

CWD="$(pwd)"
#shellcheck disable=SC1091,SC2046,SC2128
source $(dirname $(realpath "$BASH_SOURCE"))/include/common.sh

### ARG PARSE #################################################################

PROGNAME=$0

#shellcheck disable=SC2120
usage () {
	if [ -n "$*" ]; then
		message "usage error: $*"
	fi
	cat <<EOF
CVEDIA-RT Wrapper v$REDIST_VERSION

Usage: $PROGNAME [OPTIONS ...] [[-- DOCKER PARAMS ... [-- RUNTIME PARAMS ...]]]

This script is a wrapper for the CVEDIA-RT application.
It automatically detects and sets up the docker environment, exposing required devices, folders and resources to the application.

Options:
    -h, --help: Shows this message and exit

    -B, --backends: List backends available and exit
    -r, --runc: Runs using RUNC as docker runtime instead of trying to detect best runtime
    -d, --daemon: Run container in background (default is foreground)

    --gl <mode>: Set LIBGL indirect rendering, possible values are 0 or 1 (default is automatic)
                 If you have issues starting CVEDIA-RT GUI, setting this value to 0 or 1.

    -t, --tag <tag>: Overrides docker image path, including tag. This also disables automatic tag resolve.
    -b, --benchmark <model uri>: Benchmark model uri

    -C, --no_cache: Delete model cache before starting
    -L, --no_log: Do not save logs

    -A, --arch <name>: Explicitly set the architecture to use (defaults to ${ARCH})
    -Z, --dry_run: Do not run the application, just print the commands that would be executed

    -M, --cmd <command>: Overrides docker run command (defaults to cvediart)
    -R, --runtime <runtime>: Overrides docker runtime (defaults tries to detect best runtime)
    -N, --name <name>: Sets a custom name to the CVEDIA-RT container (default is cvedia-rt_<random>)
    -T, --hostname <name>: Sets a custom hostname to the CVEDIA-RT container (default is --name)
    -X, --external <name>: Runs an external script from bin.cvedia.com instead of main entrypoint

    -l, --lib <path0:path1:pathN>: Defines one or more local paths (: delimited) to search for libraries

    -g, --gst_plugins <path0:path1:pathN>: Defines one or more local paths (: delimited) to search for GStreamer plugins
    -a, --gst_plugins_auto: Automatically mount GStreamer plugins from your local /usr/lib/gstreamer-1.0

    -U, --skip_update: Do not try to pull the latest version of the docker image
    -k, --keep: Keep local caches when docker image is updated

    --skip_mount: Do not use any persistent storage. This overrides all other mount options.
    --skip_persistent: Do not mount persist folder (persist/)
    --skip_exporters: Do not mount exporters folder (exporters/)
    --skip_config: Do not use .config for environment variables

    --skip_camera: Do not mount local cameras (/dev/video*)
    --force_camera: Force camera setup even if cameras are not currently connected

    --skip_nvidia_check: Skip NVIDIA checks for nvidia docker runtime (not recommended)

    --skip_hailo: Do not mount hailo devices (/dev/hailo*)
    --force_hailo: Force hailo even when it's not detected

    --skip_rockchip: Do not try to set rockchip device frequency governor
    --force_rockchip: Force rockchip even when it's not detected
    
    --skip_qualcomm: Do not mount qualcomm dsp snpe dependencies (/dsp, /vendor)
    --force_qualcomm: Force qualcomm even when it's not detected

    -P, --skip_privileged: Do not run docker in privileged mode, may break some features
    --privileged: Force privileged mode
    --skip_jetpack_check: Do not check for jetpack version (not recommended)
    --trt_affinity <value>: Set TensorRT affinity (for NVIDIA/Jetson only), possible values are 7, 8, 8.4 (default is automatic)

    -q, --quick: Quicker less verbose startup

    -e, --extract: Extract solutions to solutions/ folder and exit
    --extract_exporters: Extract exporters to exporters/ folder end exit

    --mm <option / file path>: Defines a custom memory manager library to use (Native options: mimalloc (default), tcmalloc or a path to a file; This option adds to LD_PRELOAD)
    --nice <value>: Defines a custom nice value for CVEDIA-RT main process, default is automatic
    --taskset <value>: Defines a custom taskset cpu list for CVEDIA-RT main process, default automatic
    --blacklist <value0,value1,..>: Defines one or more CVEDIA-RT plugins to blacklist (, delimited)

    -v, --version: Prints version and exit

UI options:
    -H, --headless: Run in headless mode (no GUI)
    -m, --remote: Run in remote rendering mode (requires a client to connect to GUI)

    -K, --renderer <backend>: Set the rendering backend, possible options are:
        glfw: OpenGL (default)
        sdl: Linux SDL2 (not supported in all platforms)
        remote: Remote rendering (requires a client to connect to GUI) -- same as --remote
        headless: Headless rendering (no GUI) -- same as --headless

    --ui_port <port>: Port to expose UI when running with --renderer remote, default: 8889; Use 0 to disable exposing.
    --ui_discovery_port <port>: Automatic CVEDIA-RT discovery port. Default: 12349 (UDP); Use 0 to disable exposing.

Service options:
    --api_port <port>: Port to expose API, default: 8080; Use 0 to disable exposing.
    --rtsp_port <port>: Port to expose RTSP stream, default: 8554; Use 0 to disable exposing.
    --mqtt_port <port>: Port to expose MQTT service, default: 1883; Use 0 to disable exposing; Ignored when --disable_mqtt is set.
    
    -E, --no_expose: Do not expose any service or port; This overrides all other service / port expose options.
    --disable_mqtt: Disable internal MQTT service

    --use_image_rest_ep: Enables syncronous image rest ingestion endpoint. Requires internal MQTT service.
    
    --intent <value>: Docker intent, possible options are:
        run: Run the container (default)
        create: Create the container but do not start it

VMS options:
    --nxw: Enable NXWitness full integration mode
    --nxw_port <port>: Port to expose NXW service, default: 7001; Use 0 to disable exposing; Ignored when --nxw is not set.
    --skip_nxw_host: Disables NXWitness discovery (will run docker without --network host)
    
    --mtv: Enable NXWitness META VMS full integration mode
    --mtv_port <port>: Port to expose NXWitness META VMS service, default: 7001; Use 0 to disable exposing; Ignored when --mtv is not set.
    --skip_mtv_host: Disables NXWitness META VMS discovery (will run docker without --network host)
    
    --dwg: Enable Digital Watchdog full integration mode
    --dwg_port <port>: Port to expose Digital Watchdog service, default: 7001; Use 0 to disable exposing; Ignored when --dwg is not set.
    --skip_dwg_host: Disables Digital Watchdog discovery (will run docker without --network host)
    
    --hwv: Enable Hanwha WAVE full integration mode
    --hwv_port <port>: Port to expose Hanwha WAVE service, default: 7001; Use 0 to disable exposing; Ignored when --hwv is not set.
    --skip_hwv_host: Disables Hanwha WAVE discovery (will run docker without --network host)

    Notes:
        - Only one VMS integration can be enabled at once
        - Some VMS images might not be available depending on your CVEDIA-RT distribution
        - When running in VMS mode it's recommended to use host networking for instance discoverability

Debug options:
    -I, --interactive: Drop to a shell within docker instead of executing cvedia-rt.
    -D, --debug: Enable debug mode
    -G, --gst_debug <level>: GST debug level (default is 1) possible values are:
                             0 none, 1 error, 2 warning, 3 fixme, 4 info, 5 debug, 6 log, 7 trace, 9 memdump
    --add_symbols [path]: When avaialbe, fuse symbols with existing binaries (path defaults to /opt/cvedia-rt)
    --expose_tracy [port]: Expose tracy debug; Default port is 8086
    --core_dump_path <path>: Path to core dump folder (default is /tmp)
    --core_dump_pattern_file <path>: Path to core dump pattern file (default is /proc/sys/kernel/core_pattern)
    --disable_core_dump_persistence: Core dumps will be deleted after gdb analysis
    --ld_preload_method <method>: Switches from global LD_PRELOAD (method 0 - default) to local LD_PRELOAD (method 1)
    --disable_ld_preload: Disable automatic ld_preload of specific libraries within docker (will disable memory manager)

Note on option delimiters:
    First set of options are sent to this wrapper, adding a -- pipes options to the docker daemon.
    Adding a second -- will pipe options to cvedia-rt binary itself.

Examples:
    Run in headless mode skipping updates:
        $PROGNAME --headless -U
    
    Run in debug mode without exposing ports:
        $PROGNAME --debug --no_expose
    
    Run with explicit libgl indirect mode:
        $PROGNAME --gl 1

    Run with custom docker options:
        $PROGNAME -- --env="MY_CUSTOM_VAR=VALUE" -v /my/custom/mount:/my/custom/mount -p 1234:1234

        Note: Options after -- are sent to docker daemon

    Run with custom runtime options:
        $PROGNAME -- -- --some-runtime-option

        Note: first set of options are sent to this wrapper, options after the first -- are sent to the docker
        and options after the second -- are sent to cvedia-rt runtime binary.
    
    Run with headless with custom mounts and custom runtime options:
        $PROGNAME --headless -U -- -v /some/path/:/path/in/docker --some-docker-option -- --some-cvedia-rt-engine-option value
EOF
}

ARGS=$(getopt --options +h,H,r,d,t:,D,G:,C,L,A:,Z,U,E,M:,R:,N:,v,e,I,k,B,K:,m,T:,P,g:,a,l:,q,b:,X: \
	--long help,headless,runc,daemon,tag:,debug,gst_debug:,gst-debug:,no_cache,no-cache,no_log,no-log,arch:,dry_run,dry-run,skip_update,skip-update,skip_mount,skip-mount,skip_persistent,skip-persistent,skip_exporters,skip-exporters,skip_camera,skip-camera,force_camera,force-camera,skip_hailo,skip-hailo,force_hailo,force-hailo,skip_rockchip,skip-rockchip,skip_qualcomm,force_qualcomm,force-qualcomm,force_rockchip,force-rockchip,skip-qualcomm,skip_config,skip-config,api_port:,api-port:,rtsp_port:,rtsp-port:,mqtt_port:,mqtt-port:,no_expose,no-expose,disable_mqtt,disable-mqtt,core_dump_path:,core-dump-path:,disable_core_dump_persistence,disable-core-dump-persistence,core_dump_pattern_file:,core-dump-pattern-file:,cmd:,runtime:,gl:,name:,version,extract,interactive,keep,backends,renderer:,ui_port:,ui-port:,ui_discovery_port:,ui-discovery-port:,remote,hostname:,skip-privileged,skip_privileged,gst_plugins:,gst-plugins:,gst_plugins_auto,gst-plugins-auto,lib:,quick,intent:,use_image_rest_ep,use-image-rest-ep,benchmark:,external:,extract_exporters,extract-exporters,disable_ld_preload,disable-ld-preload,mm:,nice:,taskset:,expose_tracy::,expose-tracy::,nxw,nxw_port:,nxw-port:,skip_nxw_host,skip-nxw-host,dwg,dwg_port:,dwg-port:,skip_dwg_host,skip-dwg-host,hwv,hwv_port:,hwv-port:,skip_hwv_host,skip-hwv-host,mtv,mtv_port:,mtv-port:,skip_mtv_host,skip-mtv-host,ld_preload_method:,ld-preload-method:,skip_jetpack_check,skip-jetpack-check,trt_affinity:,trt-affinity:,blacklist:,skip_nvidia_checks,skip-nvidia-checks,add-symbols::,add_symbols::,privileged \
	--name "$PROGNAME" -- "$@")
RT=$?

if [ "$RT" != "0" ]; then
	log ERROR "Internal error; getopt exited with status $RT"
	exit 6
fi

eval set -- "$ARGS"

KEEP_CACHE=${KEEP_CACHE-0}
DOCKER_INTENT=${DOCKER_INTENT-run}
RENDERER_SET=0
VMS_SET=0
RUN_EXTRACT=0
RUN_EXTRACT_EXPORTERS=0

if [ "$#" != 0 ] ; then
    X=0
    
    while :; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -H|--headless)
                if [ "$RENDERER_SET" == "1" ] ; then
                    log ERROR "A rendering engine was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x RENDERER_SET=1
                declare -x RUN_UI=0
                declare -x RUNTIME_PARAMS="$RUNTIME_PARAMS --headless"
                ;;
            -m|--remote)
                if [ "$RENDERER_SET" == "1" ] ; then
                    log ERROR "A rendering engine was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x RENDERER_SET=1
                declare -x RUN_UI=0
                declare -x RUNTIME_PARAMS="$RUNTIME_PARAMS --remote"
                ;;
            -K|--renderer)
                if [ "$RENDERER_SET" == "1" ] ; then
                    log ERROR "A rendering engine was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x RENDERER_SET=1
                declare -x RUN_UI=0
                declare -x RUNTIME_PARAMS="$RUNTIME_PARAMS --$2"
                shift
                ;;
            -B|--backends)
                declare -x RUN_UI=0
                declare -x CVEDIA_RT_CMD="./listnndevices"
                ;;
            -b|--benchmark)
                declare -x RUN_UI=0
                declare -x CVEDIA_RT_CMD="./benchmark"
                declare -x RUNTIME_PARAMS="$RUNTIME_PARAMS -u $2"
                shift
                ;;
            -X|--external)
                declare -x RUN_UI=0
                declare -x RUN_EXTERNAL="$2"
                shift
                ;;
            
            -r|--runc) declare -x USE_RUNC=1 ;;
            -d|--daemon) declare -x DOCKER_DAEMON=1 ;;
            -q|--quick) declare -x QUICK_START=1 ;;

            --blacklist) declare -x PLUGIN_BLACKLIST="$2"; shift ;;

            --gl) declare -x LIBGL_ALWAYS_INDIRECT="$2"; shift ;;
            --intent) declare -x DOCKER_INTENT="$2"; shift ;;

            -t|--tag) declare -x TAG="$2"; shift ;;
            
            -C|--no_cache|--no-cache) declare -x NO_CACHE=1 ;;
            -L|--no_log|--no-log) declare -x NO_LOG=1 ;;
            
            -A|--arch) declare -x ARCH="$2"; shift ;;
            -Z|--dry_run|--dry-run) declare -x DRY_RUN=1 ;;

            -M|--cmd)
                x=$2
                declare -x IS_CMD=1
                
                if [ "${x:0:1}" == "." -o "${x:0:1}" == "/" ] ; then
                    declare -x CVEDIA_RT_CMD="${x}"
                else
                    declare -x CVEDIA_RT_CMD="./${x}"
                fi
                
                shift ;;
                
            -R|--runtime) declare -x RUNTIME="$2"; shift ;;
            -N|--name) declare -x CONTAINER_NAME="$2"; shift ;;
            -T|--hostname) declare -x CONTAINER_HOST="$2"; shift ;;
            
            -U|--skip_update|--skip-update) declare -x SKIP_UPDATE=1 ;;
            -k|--keep) declare -x KEEP_CACHE=1 ;;
            --skip_mount|--skip-mount) declare -x SKIP_AUTOMOUNT=1 ;;
            --skip_persistent|--skip-persistent) declare -x SKIP_PERSIST=1 ;;
            --skip_exporters|--skip-exporters) declare -x SKIP_EXPORTERS=1 ;;
            --skip_jetpack_check|--skip-jetpack-check) declare -x SKIP_JETPACK_CHECK=1 ;;
            --skip_nvidia_check|--skip-nvidia-check) declare -x SKIP_NVIDIA_CHECK=1 ;;
            --skip_camera|--skip-camera) declare -x SKIP_CAMERA=1 ;;
            --force_camera|--force-camera) declare -x FORCE_CAMERA=1 ;;
            
            --skip_hailo|--skip-hailo) declare -x SKIP_HAILO=1 ;;
            --force_hailo|--force-hailo) declare -x SKIP_HAILO=0;declare -x IS_HAILO=1 ;;
            
            --skip_rockchip|--skip-rockchip) declare -x SKIP_ROCKCHIP=1 ;;
            --force_rockchip|--force-rockchip) declare -x SKIP_ROCKCHIP=0;declare -x IS_ROCKCHIP=1 ;;
            
            --skip_qualcomm|--skip-qualcomm) declare -x SKIP_QUALCOMM=1 ;;
            --force_qualcomm|--force-qualcomm) declare -x SKIP_QUALCOMM=0;declare -x IS_QUALCOMM=1 ;;
            
            --skip_config|--skip-config) declare -x SKIP_CONFIG=1 ;;
            --privileged) declare -x FORCE_PRIVILEGED=1 ;;
            -P|--skip_privileged|--skip-privileged) declare -x SKIP_PRIVILEGED=1 ;;

            --api_port|--api-port) declare -x API_PORT="$2"; shift ;;
            --rtsp_port|--rtsp-port) declare -x RTSP_PORT="$2"; shift ;;
            --mqtt_port|--mqtt-port) declare -x MQTT_PORT="$2"; shift ;;
            --ui_port|--ui-port) declare -x UI_PORT="$2"; shift ;;
            --nxw_port|--nxw-port|--dwg_port|--dwg-port|--hwv_port|--hwv-port|--mtv_port|--mtv-port) declare -x NXW_PORT="$2"; shift ;;
            --skip_nxw_host|--skip-nxw-host|--skip_dwg_host|--skip-dwg-host|--skip_hwv_host|--skip-hwv-host|--skip_mtv_host|--skip-mtv-host) declare -x SKIP_NXW_HOST=1 ;;
            --ui_discovery_port|--ui-discovery-port) declare -x UI_DISCOVERY_PORT="$2"; shift ;;
            
            -E|--no_expose|--no-expose) declare -x NO_EXPOSE=1 ;;
            --disable_mqtt|--disable-mqtt) declare -x ENABLE_MQTT=0 ;;
            --disable_ld_preload|--disable-ld-preload) declare -x SKIP_LD_PRELOAD=1 ;;
            --ld_preload_method|--ld-preload-method) declare -x DOCKER_PARAMS="$DOCKER_PARAMS -e LD_PRELOAD_METHOD=$2"; shift ;;
            --use_image_rest_ep|--use-image-rest-ep) declare -x USE_IMAGE_REST_EP=1 ;;

            --nxw)
                if [ "$VMS_SET" == "1" ] ; then
                    log ERROR "A VMS was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x USE_NXW_PLUGIN=1
                declare -x NXW_TAG=nxw
                declare -x VMS_SET=1
                declare -x SKIP_LD_PRELOAD=1
                ;;
            --dwg)
                if [ "$VMS_SET" == "1" ] ; then
                    log ERROR "A VMS was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x USE_NXW_PLUGIN=1
                declare -x NXW_TAG=dwg
                declare -x VMS_SET=1
                declare -x SKIP_LD_PRELOAD=1
                ;;
            --hwv)
                if [ "$VMS_SET" == "1" ] ; then
                    log ERROR "A VMS was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x USE_NXW_PLUGIN=1
                declare -x NXW_TAG=hwv
                declare -x VMS_SET=1
                declare -x SKIP_LD_PRELOAD=1
                ;;
            --mtv)
                if [ "$VMS_SET" == "1" ] ; then
                    log ERROR "A VMS was already set, cannot set another one. Aborting"
                    exit 1
                fi
                declare -x USE_NXW_PLUGIN=1
                declare -x NXW_TAG=mtv
                declare -x VMS_SET=1
                declare -x SKIP_LD_PRELOAD=1
                ;;
            
            --mm) declare -x MM_OPT="$2"; shift ;;
            --nice) declare -x CRT_NICE="$2"; shift ;;
            --taskset) declare -x CRT_TASKSET="$2"; shift ;;

            -I|--interactive)
                if [ -z "$ROWS" ] ; then
                    ROWS=$(stty size | cut -d' ' -f1)
                fi
                
                if [ -z "$COLUMNS" ] ; then
                    COLUMNS=$(stty size | cut -d' ' -f2)
                fi

                declare -x USE_IT=1
                declare -x DOCKER_PARAMS="$DOCKER_PARAMS -e COLUMNS=$COLUMNS -e ROWS=$ROWS -e INTERACTIVE=1"
                ;;

            -D|--debug)
                declare -x RUN_DEBUG=1
                ;;
            --add_symbols|--add-symbols)
                declare -x DOCKER_PARAMS="$DOCKER_PARAMS -e ADD_SYMBOLS=1"
                
                if [ -n "$2" ] ; then
                    declare -x DOCKER_PARAMS="$DOCKER_PARAMS -v $2:/symbols:ro"
                    shift 2
                else
                    shift
                fi
                ;;
            --expose_tracy|--expose-tracy)
                if [ -n "$2" ] ; then
                    declare -x TRACY_PORT="$2"
                    shift 2
                else
                    declare -x TRACY_PORT="8086"
                    shift
                fi
                ;;
            -a|--gst_plugins_auto|--gst-plugins-auto) declare -x GST_PLUGIN_PATH="/usr/lib/${ARCH}-linux-gnu/gstreamer-1.0:$GST_PLUGIN_PATH" ;;
            -g|--gst_plugins|--gst-plugins) declare -x GST_PLUGIN_PATH="$2:$GST_PLUGIN_PATH"; shift ;;
            -l|--lib) declare -x CUSTOM_LIB_PATH="$2"; shift ;;
            -G|--gst_debug|--gst-debug) declare -x GST_DEBUG="$2"; shift ;;
            --core_dump_path|--core-dump-path) declare -x CORE_DUMP_PATH="$2"; shift ;;
            --core_dump_pattern_file|--core-dump-pattern-file) declare -x CORE_PATTERN_FILE="$2"; shift ;;
            --disable_core_dump_persistence|--disable-core-dump-persistence) declare -x CORE_DUMP_PERSIST=0 ;;

            -e|--extract)
                declare -x USE_IT=0
                declare -x RUN_EXTRACT=1
                declare -x SKIP_UPDATE=1
                declare -x NO_EXPOSE=1
                ;;
            --extract_exporters|--extract-exporters)
                declare -x USE_IT=0
                declare -x RUN_EXTRACT_EXPORTERS=1
                declare -x SKIP_UPDATE=1
                declare -x NO_EXPOSE=1
                ;;

            -v|--version)
                log INFO "Wrapper version v$REDIST_VERSION"
                
                if [ -f "${CRT_PATH}/.version" ] ; then
                    log INFO "Release version v$(cat ${CRT_PATH}/.version)"
                else
                    log WARN "No release version found"
                fi

                exit 0 ;;
            
            # append rest of params after -- to DOCKER_PARAMS
            # if there's another -- break, append to RUNTIME_PARAMS
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    if [ "$X" == "0" ] ; then
                        if [ "$1" == "--" ] ; then
                            X=1
                            shift
                            continue
                        fi
                        declare -x DOCKER_PARAMS="$DOCKER_PARAMS $1"
                    else
                        declare -x RUNTIME_PARAMS="$RUNTIME_PARAMS $1"
                    fi
                    shift
                done
                
                break ;;

            *) echo "Unknown option \"$1\" aborting"; exit 6 ;;
        esac
        shift
    done
fi

### UNWRAPPED LOGIC ###########################################################

if [ "$RUN_EXTRACT" == "1" ] ; then
    log INFO "-- Extracting solutions..."
    extract_assets solutions
    exit 0
fi

if [ "$RUN_EXTRACT_EXPORTERS" == "1" ] ; then
    log INFO "-- Extracting exporters..."
    extract_assets exporters
    exit 0
fi

### LOG WRAPPER ###############################################################

# wraps MAIN under a subshell for logging
if [ -z "$NO_LOG" -a -z "$IS_WRAPPED" ] ; then
    export IS_WRAPPED=1
    
    log INFO "-- Logging runner to $LOG_FN"
    
    set -o pipefail
    #shellcheck disable=SC2068
    $0 $@ | tee -a "$LOG_FN"
    RT=$?
    
    log INFO "-- Logged to: $LOG_FN"
    exit $RT
fi

### MAIN ######################################################################

log INFO "-- CVEDIA-RT Docker Wrapper v$REDIST_VERSION"
log INFO "-- ARCH: $ARCH CRT_PATH: $CRT_PATH"

resolve_docker

log DEBUG "-- GST_DEBUG: $GST_DEBUG"

if [ "$DRY_RUN" == "0" -a "$SKIP_UPDATE" == "0" ] ; then
    log DEBUG "-- CRT_REGISTRY: $CRT_REGISTRY"
    if [ "$USER_DEFINED_TAG" == "0" -a -n "$CRT_REGISTRY" -a "$(echo $CRT_REGISTRY | grep -c docker.io)" == "0" ] ; then
        NEED_LOGIN=1
        DOCKER_CFG=${DOCKER_CFG:-~/.docker/config.json}
        
        if [ -n "$DOCKER_CFG" -a -f "$DOCKER_CFG" ] ; then
            auth_str=$(cat $DOCKER_CFG | tr '\t' ' ' | tr '\n' ' ' | sed -e's/  */ /g' |  grep -o -e "\"${CRT_REGISTRY}\": {[^}]*}" | grep -o -e '"auth": "[^"]*"' | cut -d' ' -f2)
            if [ "${#auth_str}" -lt 4 ]; then
                NEED_LOGIN=1
            else
                NEED_LOGIN=0
            fi
        fi

        if [ "$NEED_LOGIN" != "0" ] ; then
            log WARN "-- You need to login to the docker registry: $CRT_REGISTRY to be able to pull the CVEDIA-RT image."
            log WARN "-- Credentials were provided in the release email"
            log WARN "-- We will try to log you in now, if succeeded, credentials will be saved at $DOCKER_CFG"
            log WARN "-- Please provide credentials below:"
            
            #shellcheck disable=SC2153
            $DOCKER_CMD login $CRT_REGISTRY
            RT=$?
            if [ "$RT" != "0" ] ; then
                log ERROR "-- Failed logging in, aborting"
                exit 1
            fi
        fi
    fi
    
    log INFO "-- Pulling docker image: ${TAG}..."

    # get current image hash
    CTAG=$($DOCKER_CMD inspect --format '{{json .RepoDigests}}' $TAG | cut -d ':' -f2 | cut -d'"' -f1)
    set -x
    $DOCKER_CMD pull $TAG
    RT=$?
    set +x
    check_exit $RT "Failed to pull docker image: ${TAG}"
    NTAG=$($DOCKER_CMD inspect --format '{{json .RepoDigests}}' $TAG | cut -d ':' -f2 | cut -d'"' -f1)

    if [ -n "$CTAG" -a -n "$NTAG" -a "$CTAG" != "$NTAG" ] ; then
        log DEBUG "-- Docker image updated from: $CTAG to: $NTAG"
    fi

    # new and old tag are not empty and not matching and keep_cache is 0 and models folder exist
    if [ "$KEEP_CACHE" == "0" -a -n "$CTAG" -a -n "$NTAG" -a "$CTAG" != "$NTAG" -a -d "${CRT_PATH}/models" ] ; then
        log INFO "-- Docker image updated, removing caches"
        rm -fr ${CRT_PATH}/models/* &> /dev/null
    fi
fi

### CONFIGURE DOCKER ##########################################################

log INFO "-- Running docker image: ${TAG} as ${CONTAINER_NAME}..."

DOCKER_PARAMS="$DOCKER_PARAMS --name ${CONTAINER_NAME} --hostname ${CONTAINER_HOST}"

for i in DOCKER_PARAMS DOCKER_MNT DOCKER_PORTS RUNTIME_PARAMS; do
    log DEBUG "-- ${i}: ${!i}"
done

### RUN DOCKER ################################################################

read -r -d '' cmd << EOF
$DOCKER_CMD ${DOCKER_INTENT} \
    $DOCKER_MNT $DOCKER_PARAMS $DOCKER_PORTS \
    $TAG $RUNTIME_PARAMS
EOF

# clean cache
if [ "$NO_CACHE" == "1" ] ; then
    log INFO "-- Removing any existing caches..."
    if [ "$DRY_RUN" == "1" ] ; then
        log DEBUG "-- DRY_RUN enabled: skipping cache removal"
    else
        rm -fr models/* persist/cvediart.key &> /dev/null
    fi
fi

if [ -n "$LOG_FN" ] ; then
    env >> "$LOG_FN"
fi

log INFO "-- Running: ${cmd}"

if [ "$DRY_RUN" == "1" ] ; then
    log WARN "-- DRY_RUN enabled: skipping docker run."
    exit 0
fi

# make sure there's no existing conflicting name container running
$DOCKER_CMD container kill ${CONTAINER_NAME} &> /dev/null
$DOCKER_CMD container rm ${CONTAINER_NAME} &> /dev/null

# https://stackoverflow.com/a/6872163/163882
# https://unix.stackexchange.com/questions/124590
# when using quotes directly running $cmd will unescape them, eval is safer
eval $cmd
RT=$?
log INFO "-- Exit code: ${RT}, ran for ${SECONDS}s"
exit $RT
