#!/bin/bash
#shellcheck disable=SC2166

#shellcheck disable=SC1091
source $(dirname $(realpath $BASH_SOURCE))/env.sh

rand() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo ''    
}

log () {
    if [ "$NO_COLOR" == "1" ] ; then
        ERROR=
        INFO=
        WARN=
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
        IN="${@:2}"
    else
        read -r IN
    fi

    local TS
    TS=$(date +%Y-%m-%d\ %H:%M:%S.%N)
    echo -e "${C_N}${!level}${TS::-6} $HOSTNAME $level [$$] $IN${C_N}"
}

check_exit () {
    RT=$1
    ERROR_MESSAGE=${@:2}
    if [ "$RT" != "0" ]; then
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

activate_conda() {
    if [ ! -d "${ANACONDA_ROOT}/envs/${ANACONDA_ENV}" ] ; then
        log WARN "Conda env: ${ANACONDA_ENV} is not yet installed, skipping activation"
    else
        # https://github.com/conda/conda/issues/7980#issuecomment-441358406
        log INFO "Activating conda env: ${ANACONDA_ENV}..."
        source "${ANACONDA_ROOT}/etc/profile.d/conda.sh"
        conda activate "${ANACONDA_ENV}"
        # fixes issue with /usr/lib/x86_64-linux-gnu/libstdc++.so.6 missing symbols
        declare -x LD_LIBRARY_PATH=${ANACONDA_ROOT}/envs/${ANACONDA_ENV}/lib/:${LD_LIBRARY_PATH}
        ldconfig &> /dev/null
    fi
}

checkout_repo() {
    CWD="$(pwd)"
    
    REPO="$1"
    BASE_DIR="$2"
    BASE_BRANCH="$3"
    BASE_BRANCH_CMD=
    #GIT_SSH_COMMAND='ssh -v'

    if [ -n "$BASE_BRANCH" ]; then
        BASE_BRANCH_CMD=" git checkout ${BASE_BRANCH}"
    fi

    if [ -z "$BASE_DIR" ] ; then
        log ERROR "Checkout BASE_DIR is not set, aborting"
        exit 1
    fi

    REPO_NAME=$(echo "${REPO}" | rev | cut -d'/' -f1 | rev)

    if [ ! -d "${BASE_DIR}/.git" ] ; then # clone
        log INFO "Cloning repo ${REPO_NAME} from ${REPO}..."
        #git clone "$REPO" "$BASE_DIR" --depth 1 --no-single-branch --progress ${BASE_BRANCH_CMD}
        git clone "$REPO" "$BASE_DIR" --recursive --progress
        check_exit $? "Failed to clone repository: $REPO"
        #shellcheck disable=SC2164
        cd "$BASE_DIR"
        check_exit $? "Failed to change directory to: $BASE_DIR"
        ${BASE_BRANCH_CMD}
        check_exit $? "Failed on ${BASE_BRANCH_CMD}"
    else
        log INFO "Updating current branch of ${REPO_NAME} from ${REPO}..."
        #cd "${BASE_DIR}" && git pull --allow-unrelated-histories
        # NOTE: --allow-unrelated-histories is only available at new versions of git
        #shellcheck disable=SC2164
        cd "${BASE_DIR}"
        check_exit $? "Failed to change directory to: $BASE_DIR"
        git checkout master
        check_exit $? "Failed to checkout master"
        git pull --all --rebase
        check_exit $? "Failed to rebase"

        if [ -n "${BASE_BRANCH}" ] ; then # not in master
            #shellcheck disable=SC2164
            cd "${BASE_DIR}"
            check_exit $? "Failed to change directory to: $BASE_DIR"
            ${BASE_BRANCH_CMD}
            check_exit $? "Failed on ${BASE_BRANCH_CMD}"
        fi
    fi
}

resolve_docker() {
    
    # internal defaults - overriden earlier by run.sh argparse
    SKIP_CONFIG=${SKIP_CONFIG-0}
    SKIP_AUTOMOUNT=${SKIP_AUTOMOUNT-0}
    SKIP_CAMERA=${SKIP_CAMERA-0}
    SKIP_UPDATE=${SKIP_UPDATE-0}
    SKIP_PERSIST=${SKIP_PERSIST-0}
    SKIP_EXPORTERS=${SKIP_EXPORTERS-0}
    SKIP_TRT_SELECTOR=${SKIP_TRT_SELECTOR-0}
    SKIP_NVIDIA_CHECK=${SKIP_NVIDIA_CHECK-0}
    SKIP_HAILO=${SKIP_HAILO-0}
    SKIP_QUALCOMM=${SKIP_QUALCOMM-0}
    SKIP_ROCKCHIP=${SKIP_ROCKCHIP-0}
    SKIP_PRIVILEGED=${SKIP_PRIVILEGED-0}
    SKIP_LD_PRELOAD=${SKIP_LD_PRELOAD-0}
    SKIP_NXW_HOST=${SKIP_NXW_HOST-0}
    SKIP_JETPACK_CHECK=${SKIP_JETPACK_CHECK-0}
    
    QUICK_START=${QUICK_START-0}
    FORCE_CAMERA=${FORCE_CAMERA-0}

    IS_ROCKCHIP=${IS_ROCKCHIP-0}
    IS_QUALCOMM=${IS_QUALCOMM-0}
    IS_JETSON=${IS_JETSON-0}
    IS_HAILO=${IS_HAILO-0}
    IS_CMD=${IS_CMD-0}

    USE_IMAGE_REST_EP=${USE_IMAGE_REST_EP-0}
    USE_NXW_PLUGIN=${USE_NXW_PLUGIN-0}
    NXW_TAG=${NXW_TAG-nxw}

    NO_EXPOSE=${NO_EXPOSE-0}

    RUN_UI=${RUN_UI-1}
    RUN_STANDALONE=${RUN_STANDALONE-1}
    DRY_RUN=${DRY_RUN-0}

    USER_DEFINED_TAG=0
    INTERNAL_API_PORT=${INTERNAL_API_PORT-8080}
    UI_DISCOVERY_PORT=${UI_DISCOVERY_PORT-12349}
    
    FORCE_PRIVILEGED=${FORCE_PRIVILEGED-0}
    NEED_PRIVILEGED=${FORCE_PRIVILEGED-0}

    MM_OPT=${MM_OPT-mimalloc}

    if [ "$DRY_RUN" == "1" ] ; then
        log WARN "-- DRY_RUN enabled"
    fi

    if [ "$SKIP_CONFIG" == "0" -a -f "${CRT_PATH}/.config" ] ; then
        log INFO "-- Importing ${CRT_PATH}/.config..."
        source "${CRT_PATH}/.config"
        cat "${CRT_PATH}/.config"
    fi

    # if REST is enabled, MQTT must be running; No need to expose it tho.
    if [ "$USE_IMAGE_REST_EP" == "1" ] ; then
        log WARN "-- Running in Image REST EP mode, disabling UI and enabling MQTT..."
        ENABLE_MQTT=1
        RUN_STANDALONE=0
        RUN_UI=0
        INTERNAL_API_PORT=80
    fi

    # Container name, if a container with this name exists it will be killed and removed before running
    CONTAINER_NAME=${CONTAINER_NAME-cvedia-rt_$(echo $RANDOM | md5sum | head -c 10)}
    CONTAINER_HOST=${CONTAINER_HOST-$CONTAINER_NAME}

    # Container service ports
    # NOTE: This has no effect when running on jetpack 4.5 or older, since we need to run with --net=host

    ENABLE_MQTT=${ENABLE_MQTT-1}
    
    API_PORT=${API_PORT-8080}
    RTSP_PORT=${RTSP_PORT-8554}
    MQTT_PORT=${MQTT_PORT-1883}
    UI_PORT=${UI_PORT-8889}
    NXW_PORT=${NXW_PORT-7001}

    GST_DEBUG=${GST_DEBUG-1}

    # When set to 1 will use runc docker runtime instead of nvidia-docker
    USE_RUNC=${USE_RUNC-0}

    # add -it to DOCKER_PARAMS
    USE_IT=${USE_IT-1}

    # docker binary to call
    DOCKER_CMD="docker"
    
    # Runs CVEDIA-RT GUI, requires a X11 session to be running
    RUN_UI=${RUN_UI-1}
    
    # Daemonize instead of running in foreground
    DOCKER_DAEMON=${DOCKER_DAEMON-0}
    
    # CVEDIA-RT startup command
    CVEDIA_RT_CMD="${CVEDIA_RT_CMD-./cvediart}"
    log DEBUG "-- CVEDIA_RT_CMD: $CVEDIA_RT_CMD"
    
    if [ "$QUICK_START" == "0" ] ; then
        if [ -n "$(command -v uname)" ] ; then
            log DEBUG "-- UNAME: $(uname -a)"
        fi

        if [ -n "$(command -v lsb_release)" ] ; then
            log DEBUG "-- LSB_RELEASE: $(lsb_release -a 2>/dev/null)"
        fi

        if [ -e "/proc/cpuinfo" ] ; then
            log DEBUG "-- CPUINFO: $(sort /proc/cpuinfo | uniq)"
        fi
    fi

    DOCKER_PARAMS="${DOCKER_PARAMS} -e CVEDIA_RT_CMD=\"${CVEDIA_RT_CMD}\""
    DOCKER_MNT=${DOCKER_MNT:-}

    # CVEDIA-RT registry, if set but empty, will assume a local image, otherwise will use the default repository
    if [ -z "${CRT_REGISTRY+x}" -a -f "${CRT_PATH}/.registry" ] ; then
        CRT_REGISTRY=$(cat "${CRT_PATH}/.registry")/
    else
        CRT_REGISTRY=docker.io/
    fi

    # user explicitly set a TAG, we won't touch it
    if [ -n "$TAG" ] ; then
        SKIP_TRT_SELECTOR=1
        USER_DEFINED_TAG=1

        # fix CRT_REGISTRY
        CRT_REGISTRY=$(echo "$TAG" | cut -d '/' -f 1)/
        if [ "$CRT_REGISTRY" == "cvedia/" ] ; then
            CRT_REGISTRY="docker.io/"
        fi
    fi

    # Image tag to run
    if [ -z "$TAG" -a -f "${CRT_PATH}/.tag" ] ; then
        TAG="${CRT_REGISTRY}$(cat "${CRT_PATH}/.tag")"
        TAG=${TAG/\#\#ARCH\#\#/${ARCH}}
    fi
    
    # fallback to latest, this might not work in all cases
    if [ -z "$TAG" ] ; then
        TAG=${TAG-${CRT_REGISTRY}cvedia/rt:runtime-${ARCH}-public}
        log WARNING "-- No image tag specified, using default: ${TAG}"
    fi

    if [ "$ARCH" == "aarch64" ] ; then
        # qualcomm soc
        if [ "$SKIP_QUALCOMM" == "0" -a "$(grep -ic qualcomm /proc/cpuinfo 2> /dev/null)" -gt "0" ] ; then
            IS_QUALCOMM=1
            log INFO "-- Detected Qualcomm CPU, enabling privileged mode"
            NEED_PRIVILEGED=1
            # comes from device bios / custom partittion, dynamically loaded by libSNPE
            if [ -d "/dsp" ] ; then
                log DEBUG "-- Found /dsp folder"
                DOCKER_MNT="$DOCKER_MNT -v /dsp:/dsp"
            else
                log ERROR "-- Detected Qualcomm CPU but no /dsp folder found, SNPE inference driver might not work."
            fi
            
            # might contain additional drivers
            if [ -d "/vendor" ] ; then
                log DEBUG "-- Found /vendor folder"
                DOCKER_MNT="$DOCKER_MNT -v /vendor:/vendor"
            fi
        fi

        if [ "$SKIP_ROCKCHIP" == "0" -a "$(cat /sys/devices/platform/*.npu/uevent 2> /dev/null | grep -ci rockchip)" -gt "0" ] ; then
            log INFO "-- Detected Rockchip NPU"
            IS_ROCKCHIP=1
            log DEBUG "-- Rockchip detected, enabling privileged mode"
            NEED_PRIVILEGED=1
        fi
        
        # jetpack
        if [ -f "/etc/nv_tegra_release" ] ; then
            IS_JETSON=1
            # fix for loading gst plugins
            DOCKER_PARAMS="${DOCKER_PARAMS} -e LD_PRELOAD=libgomp.so.1 -v /etc/nv_tegra_release:/etc/nv_tegra_release:ro"

            # if [ -e "/sys/firmware/devicetree/base/serial-number" ] ; then
            #     DOCKER_PARAMS="${DOCKER_PARAMS} -v /sys/firmware/devicetree/base/serial-number:/sys/firmware/devicetree/base/serial-number:ro"
            # fi
            
            # jetpack 5+:
            # R35 (release), REVISION: 1.0, GCID: 31346300, BOARD: t186ref, EABI: aarch64, DATE: Thu Aug 25 18:41:45 UTC 2022
            if [ -z "$L4T" -o -z "$L4R" ] ; then
                log DEBUG "-- Tegra full release: $(cat /etc/nv_tegra_release)"
                L4R=$(cat /etc/nv_tegra_release | cut -d' ' -f2)
                L4R=${L4R//R/}
                L4T=$(cat /etc/nv_tegra_release | cut -d' ' -f5 | cut -d',' -f1)
                log DEBUG "-- L4T ${L4R}.${L4T}"

                if [ -z "$L4R" -o -z "$L4T" ] ; then
                    log ERROR "-- Unable to properly detect L4T version, please set L4R and L4T manually."
                    log ERROR "-- Please check if your jetpack release listed in the documentation at https://docs.cvedia.com/"

                    if [ "$SKIP_JETPACK_CHECK" == "0" ] ; then
                        exit 1
                    else
                        log ERROR "-- Skipping jetpack check"
                    fi
                fi
            else
                log INFO "-- Using user defined L4R: $L4R L4T: $L4T"
            fi
            
            # jetpack 5.0.1+
            if [ "$L4R" == "35" ] ; then
                TRT_AFFINITY=8.4
                log INFO "-- Jetpack 5.x detected"
                DOCKER_MNT="$DOCKER_MNT -v /run:/run"

                # might not be needed, but for compatibility shake...
                log DEBUG "-- L4R.35, enabling privileged mode"
                NEED_PRIVILEGED=1
            # jetpack 5 and EA -- NOT SUPPORTED
            # elif [ "$L4R" == "34" ] ; then
            #     TRT_AFFINITY=8.2
            #     log INFO "-- Jetpack 5.0 detected"
            #     DOCKER_MNT="$DOCKER_MNT -v /run:/run"
            elif [ "$L4R" == "32" ] ; then
                # 6.1 -> jetpack 4.{6.1} -> 61
                L4T=${L4T//./}

                if [ "$L4T" -lt "43" -o "$L4T" -gt "64" ] ; then
                    log ERROR "The currently installed version of jetpack is not supported."
                    log ERROR "$(cat /etc/nv_tegra_release)"

                    if [ "$SKIP_JETPACK_CHECK" == "0" ] ; then
                        if [ "$L4T" -gt "64" ] ; then # EA / unknown versions
                            log ERROR "Please install jetpack 4.6.x -- https://developer.nvidia.com/jetpack-sdk-46"
                        else # too old
                            log ERROR "Please upgrade to 4.6.x -- https://developer.nvidia.com/jetpack-sdk-46"
                        fi

                        log ERROR "You can ignore this error by sending --skip_jetpack_check"
                        exit 1
                    else
                        log ERROR "-- Skipping jetpack version check"
                    fi
                elif [ "$L4T" -lt "60" ] ; then
                    # older jetpack requires privileged mode to work
                    log DEBUG "-- L4R.32, enabling privileged mode"
                    NEED_PRIVILEGED=1
                    
                    if [ "$SKIP_PRIVILEGED" == "0" ] ; then
                        DOCKER_PARAMS="$DOCKER_PARAMS --net=host --ipc=host"
                    else
                        log DEBUG "-- Skipping privileged mode"
                    fi
                fi

                DOCKER_MNT="$DOCKER_MNT -v /run:/run"

                # double check libnvinfer
                # shellcheck disable=1001
                NVINFER=$(find $(ldconfig -pv | grep \/libnvinfer\.so\. | cut -d'>' -f2 | tr -d ' ').* -type f | head -n1 | cut -d'.' -f3-)
                
                if [ -z "$TRT_AFFINITY" -a -n "$NVINFER" -a "$SKIP_TRT_SELECTOR" == "0" ] ; then
                    if [ "$L4T" -ge "60" -o "${NVINFER:0:1}" == "8" ] ; then
                        TRT_AFFINITY=8
                    elif [ "$L4T" -lt "60" -o "${NVINFER:0:1}" == "7" ] ; then
                        TRT_AFFINITY=7
                    else
                        log ERROR "-- Unable to find TensorRT affinity, assuming TensorRT 7."
                        TRT_AFFINITY=7
                    fi
                fi
            else
                log ERROR "-- Unsupported L4T release:"
                log ERROR "$(cat /etc/nv_tegra_release)"
                log ERROR "-- Please contact support or use a release listed in the documentation at https://docs.cvedia.com/"

                if [ "$SKIP_JETPACK_CHECK" == "0" ] ; then
                    exit 1
                else
                    log ERROR "-- Skipping jetpack check"
                fi
            fi

            if [ "$SKIP_TRT_SELECTOR" == "0" -a -n "$TRT_AFFINITY" ] ; then
                log DEBUG "-- Appending TRT_AFFINITY: $TRT_AFFINITY to $TAG"
                TAG=${TAG}-trt${TRT_AFFINITY}
            fi
        fi
    fi

    if [ "$FORCE_CAMERA" == "1" -o "$SKIP_CAMERA" == "0" ] ; then
        k=$(find /dev/video* 2>/dev/null | wc -l)
        if [ "$k" -gt "0" ] ; then
            log INFO "-- Found $k video devices at /dev"
            if [ -e "/etc/xdg" ] ; then
                DOCKER_MNT="$DOCKER_MNT -v /etc/xdg:/etc/xdg"
            fi

            # if not root, check if privileged mode is needed to be able to read from camera(s)
            if [[ $EUID -ne 0 ]]; then
                for k in $(find /dev/video*); do
                    if [ ! -r "$k" ] ; then
                        log DEBUG "-- Cannot read camera: $k, enabling privileged mode"
                        NEED_PRIVILEGED=1
                    fi
                done
            fi

            # jetson
            if [ -f "/tmp/argus_socket" ]  ; then
                DOCKER_MNT="$DOCKER_MNT -v /tmp/argus_socket:/tmp/argus_socket"
            fi
        fi
    elif [ -f "/tmp/argus_socket" ]  ; then
        DOCKER_MNT="$DOCKER_MNT -v /tmp/argus_socket:/tmp/argus_socket"
        if [ -e "/etc/xdg" ] ; then
            DOCKER_MNT="$DOCKER_MNT -v /etc/xdg:/etc/xdg"
        fi
    fi

    if [ "$SKIP_HAILO" == "0" ] && [ "$IS_HAILO" == "1" -o "$(find /dev/hailo* 2>/dev/null | wc -l)" -gt "0" ] ; then
        K=$(find /dev/hailo* 2>/dev/null | wc -l)
        log INFO "-- Found HAILO ${K} devices"
        IS_HAILO=1

        # find libhailort and mount it
        if [ -n "$(command -v ldconfig)" ] ; then
            HAILO_LIB=$(ldconfig -vNp | grep 'libhailort\.so\.' | rev | cut -d' ' -f1 | rev | head -n1)
        fi
        
        # slow, but maybe maybe
        if [ -z "$HAILO_LIB" ] ; then
            HAILO_LIB=$(find /usr/lib /lib /usr/local/lib -type f -name 'libhailort.so.*' 2>/dev/null | head -n1)
        fi

        # hailort is missing / not loaded / weird path
        if [ -z "$HAILO_LIB" ] ; then
            log ERROR "-- Unable to find libhailort.so using ldconfig / find"
            log ERROR "-- Please install HailoRT and kernel modules or specify --skip-hailo to skip loading hailo."
            exit 1
        fi

        log INFO "-- Found HAILO library at $HAILO_LIB"
        DOCKER_PARAMS="$DOCKER_PARAMS -v ${HAILO_LIB}:/usr/lib/libhailort.so:ro"
        
        for h in $(find /dev/hailo*); do
            # if not root, check if we have rw access to the device
            if [[ $EUID -ne 0 ]]; then
                if [ ! -r "$h" -o ! -w "$h" ] ; then
                    log DEBUG "-- Cannot rw to hailo device: $h, enabling privileged mode"
                    NEED_PRIVILEGED=1
                fi
            fi
            
            DOCKER_PARAMS="$DOCKER_PARAMS --device=$h"
        done
    fi

    if [ "$SKIP_AUTOMOUNT" == "0" ] ; then
        mkdir -p "${CRT_PATH}/output" "${CRT_PATH}/persist" "${CRT_PATH}/models" "${CRT_PATH}/instances/My Instances" &> /dev/null
        
        if [ "$USE_NXW_PLUGIN" == "1" ] ; then
            declare -x ENABLE_MQTT=0
            
            if [ "$NXW_TAG" == "nxw" ] ; then
                L_NXW_PATH=nxwitness
                D_NXW_PATH=networkoptix
            elif [ "$NXW_TAG" == "dwg" ] ; then
                L_NXW_PATH=digitalwatchdog
                D_NXW_PATH=digitalwatchdog
            elif [ "$NXW_TAG" == "hwv" ] ; then
                L_NXW_PATH=hanwha
                D_NXW_PATH=hanwha
            elif [ "$NXW_TAG" == "mtv" ] ; then
                L_NXW_PATH=metavms
                D_NXW_PATH=networkoptix-metavms
            else
                log ERROR "-- Unsupported VMS plugin tag: $NXW_TAG"
                exit 1
            fi

            mkdir -p "${CRT_PATH}/configs" "${CRT_PATH}/${L_NXW_PATH}/home" "${CRT_PATH}/${L_NXW_PATH}/config" "${CRT_PATH}/${L_NXW_PATH}/recordings" "${CRT_PATH}/${L_NXW_PATH}/etc" "${CRT_PATH}/${L_NXW_PATH}/var" &> /dev/null
            
            for i in analytics_logging.ini cvediart.ini db_helper.ini nx_build_info.ini nx_network.ini nx_network_rest.ini nx_streaming.ini nx_utils.ini nx_vms_server.ini resource_management.ini test_camera.ini vivotek_analytics_plugin.ini vms_server_hanwha.ini vms_server_plugins.ini vms_server_raid_event.ini; do
                touch "${CRT_PATH}/${L_NXW_PATH}/home/${i}" &> /dev/null
            done

            if [ -n "$PLUGIN_BLACKLIST" ] ; then
                PLUGIN_BLACKLIST="${PLUGIN_BLACKLIST},remote,rtglfw,sdl"
            else
                PLUGIN_BLACKLIST="remote,rtglfw,sdl"
            fi
            
            DOCKER_MNT="$DOCKER_MNT -v ${CRT_PATH}/${L_NXW_PATH}/home:/root/.config/nx_ini -v ${CRT_PATH}/${L_NXW_PATH}/config:/config -v ${CRT_PATH}/${L_NXW_PATH}/recordings:/archive -v ${CRT_PATH}/${L_NXW_PATH}/etc:/opt/${D_NXW_PATH}/mediaserver/etc -v ${CRT_PATH}/${L_NXW_PATH}/var:/opt/${D_NXW_PATH}/mediaserver/var"
            DOCKER_PARAMS="$DOCKER_PARAMS -e NXW_PATH=${D_NXW_PATH}"
        fi

        # /opt/cvedia-rt/assets/
        for i in projects videos images exports models; do
            if [ -e "${CRT_PATH}/${i}" ] ; then
                log INFO "-- Automatic mounting: ${CRT_PATH}/${i} to assets"
                DOCKER_MNT="$DOCKER_MNT -v ${CRT_PATH}/${i}:/opt/cvedia-rt/assets/$i"
            fi
        done
        
        # /opt/cvedia-rt/
        for i in output instances solutions configs; do
            if [ -e "${CRT_PATH}/${i}" ] ; then
                log INFO "-- Automatic mounting: ${CRT_PATH}/${i}"
                DOCKER_MNT="$DOCKER_MNT -v ${CRT_PATH}/${i}:/opt/cvedia-rt/$i"
            fi
        done

        # /opt/cvedia-rt/persist/
        if [ "$SKIP_PERSIST" == "0" ] ; then
            for i in persist; do
                if [ -e "${CRT_PATH}/$i" ] ; then
                    log INFO "-- Automatic mounting: ${CRT_PATH}/${i} to root"
                    DOCKER_MNT="$DOCKER_MNT -v ${CRT_PATH}/${i}:/opt/cvedia-rt/$i"
                fi
            done
        fi

        # /opt/cvedia-rt/exporters/
        if [ "$SKIP_EXPORTERS" == "0" ] ; then
            if [ -e "${CRT_PATH}/exporters" ] ; then
                DOCKER_MNT="$DOCKER_MNT -v ${CRT_PATH}/exporters:/opt/cvedia-rt/exporters"
            fi
        fi
    fi

    for i in /dev /etc/timezone /etc/machine-id /var/lib/dbus/machine-id /lib/firmware /sys/firmware /etc/drirc; do
        if [ -e "${i}" ] ; then
            DOCKER_MNT="$DOCKER_MNT -v ${i}:${i}:ro"
        fi
    done
    
    # replicate timezone from host
    if [ -e "/etc/timezone" -a -z "$TZ" ] ; then
        DOCKER_PARAMS="${DOCKER_PARAMS} -e TZ=$(cat /etc/timezone)"
    fi

    if [ "$RUN_UI" == "1" ] ; then
        if [ ! -d "/tmp/.X11-unix" ] ; then
            log WARN "-- No X11 socket found, UI will not be available"
            RUN_UI=0
        else
            DOCKER_MNT="$DOCKER_MNT -v /tmp/.X11-unix:/tmp/.X11-unix"
            if [ -n "$(command -v xhost)" ] ; then
                log INFO "-- Setting X11 to accept connections from anywhere"
                RT=0
                if [[ $EUID -ne 0 ]]; then
                    if [ -z "$DISPLAY" ]; then
                        DISPLAY_GUESS=$(ps e -u "$USER" | sed -rn 's/.* DISPLAY=(:[0-9]*).*/\1/p' | uniq | head -n1)
                        if [ -n "$DISPLAY_GUESS" ] ; then
                            log DEBUG "-- Guessed $USER user display to $DISPLAY_GUESS"
                            DISPLAY=$DISPLAY_GUESS
                        else
                            log WARN "-- Unable to find a display, falling back to :0"
                            DISPLAY=:0
                        fi
                    fi
                    
                    if [ "$DRY_RUN" == "0" ] ; then
                        DISPLAY=${DISPLAY} xhost + &> /dev/null
                        RT=$?
                    fi
                else # running as root
                    GUESS="$(w | grep xdm | cut -d' ' -f1 | head -n1)"
                    
                    if [ -n "$GUESS" ] ; then
                        log DEBUG "-- Guessed xdm user to $GUESS"
                        if [ -z "$DISPLAY" ] ; then
                            DISPLAY_GUESS=$(ps e -u "$GUESS" | sed -rn 's/.* DISPLAY=(:[0-9]*).*/\1/p' | uniq | head -n1)
                            if [ -n "$DISPLAY_GUESS" ] ; then
                                log DEBUG "-- Guessed $GUESS user display to $DISPLAY_GUESS"
                                DISPLAY=$DISPLAY_GUESS
                            else
                                log WARN "-- Unable to find a display, falling back to :0"
                                DISPLAY=:0
                            fi
                        fi

                        if [ "$DRY_RUN" == "0" ] ; then
                            runuser -l $GUESS -c "DISPLAY=$DISPLAY xhost + &> /dev/null"
                            RT=$?
                        fi
                    else
                        if [ "$DRY_RUN" == "0" ] ; then
                            DISPLAY=$DISPLAY xhost + &> /dev/null
                            RT=$?
                        fi
                    fi
                fi
                
                if [ "$DRY_RUN" == "0" -a "$RT" != "0" ] ; then
                    log WARN "-- Failed to setup XHOST display, UI might not work properly; Try running this script from within the window manager."
                fi
            else
                log WARN "-- xhost not found, connection between host and container may not work"
            fi
        fi

        if [ -z "$DISPLAY" ] ; then
            log WARN "-- No DISPLAY set, assuming :0"
            DISPLAY=:0
        fi

        log DEBUG "-- DISPLAY: $DISPLAY"
        # best guess for LIBGL_ALWAYS_INDIRECT value
        if [ -z "$LIBGL_ALWAYS_INDIRECT" ] ; then
            log DEBUG "-- LIBGL_ALWAYS_INDIRECT not set, checking glxinfo"
            if [ -n "$(command -v glxinfo)" ] ; then
                ginfo=$(DISPLAY=$DISPLAY glxinfo 2>/dev/null | grep 'direct rendering' | cut -d':' -f2 | tr -d ' ')
                log DEBUG "-- glxinfo output: $ginfo"
                
                if [ "$ginfo" == "Yes" ] ; then
                    LIBGL_ALWAYS_INDIRECT=0
                elif [ "$ginfo" == "No" ] ; then
                    LIBGL_ALWAYS_INDIRECT=1
                else
                    log WARN "-- Unable to determine LIBGL_ALWAYS_INDIRECT value, if you get opengl errors please try setting LIBGL_ALWAYS_INDIRECT manually to either 1 or 0."
                fi
                
                if [ -n "$LIBGL_ALWAYS_INDIRECT" ] ; then
                    log DEBUG "-- Setting LIBGL_ALWAYS_INDIRECT to $LIBGL_ALWAYS_INDIRECT"
                fi
            else
                log DEBUG "-- glxinfo not installed, unable to find current rendering method"
            fi
        else
            log INFO "-- Using predefined LIBGL_ALWAYS_INDIRECT: $LIBGL_ALWAYS_INDIRECT"
        fi
    fi

    if [ -z "$RUNTIME" ] ; then
        if [[ "$ARCH" == "aarch64" && ! -f "/etc/nv_tegra_release" ]] || [[ "$ARCH" =~ "arm" ]] ; then
            log INFO "-- Detected ARM architecture, but not NVIDIA, using RUNC as docker runtime."
            USE_RUNC=1
        fi

        # check if nvidia docker exists and is sane
        if [ "$USE_RUNC" == "0" ] ; then
            # nvidia docker binary exists
            if [ -n "$(command -v nvidia-docker)" ] ; then
                log INFO "-- Found nvidia-docker binary"
                DOCKER_CMD="nvidia-docker"
            elif [ -n "$(command -v nvidia-docker2)" ] ; then
                log INFO "-- Found nvidia-docker2 binary"
                DOCKER_CMD="nvidia-docker2"
            # nvidia drivers are present
            elif [ -n "$(command -v nvidia-smi)" -o -n "$(command -v tegrastats)" -o -f "/etc/nv_tegra_release" ] ; then
                # double check to see if nvidia-docker is installed but docker runtime binary is not a standard name
                if [ "$(docker info -f '{{.Runtimes}}' | grep -c nvidia)" -gt "0" ] ; then
                    log INFO "-- Using NVIDIA docker as runtime option"
                    DOCKER_PARAMS="$DOCKER_PARAMS --runtime nvidia"
                else
                    log ERROR "-- NVIDIA drivers / hardware found, but no NVIDIA docker runtime found."
                    log ERROR "-- For maximum performance you can install NVIDIA docker runtime with the following: https://github.com/NVIDIA/nvidia-container-runtime"
                    if [ "$SKIP_NVIDIA_CHECK" == "0" ] ; then
                        log ERROR "-- To bypass this error use --skip-nvidia-check"
                        exit 1
                    else
                        log ERROR "-- NVIDIA CHECKS are disable, continuing with runc as runtime."
                        USE_RUNC=1
                    fi
                fi
            # nothing nvidia found, use runc
            else
                log WARN "-- NVIDIA docker not found, falling back to RUNC"
                USE_RUNC=1
            fi

            # NOTE: When a GPU is present LIBGL is mostly likely working indirectly
            # if there's no glxinfo installed, we cannot guess it.
            if [ "$USE_RUNC" == "0" -a "$RUN_UI" == "1" ] ; then
                DOCKER_PARAMS="$DOCKER_PARAMS -e LIBGL_ALWAYS_INDIRECT=${LIBGL_ALWAYS_INDIRECT-1}"
            fi
        fi
        
        if [ "$USE_RUNC" == "1" ] ; then
            log INFO "-- Using RUNC docker runtime"
            DOCKER_PARAMS="$DOCKER_PARAMS --runtime runc"
            
            if [ "$RUN_UI" == "1" ] ; then
                DOCKER_PARAMS="$DOCKER_PARAMS -e LIBGL_ALWAYS_INDIRECT=${LIBGL_ALWAYS_INDIRECT-0}"
            fi
        fi
    else
        log INFO "-- Using user defined docker runtime: $RUNTIME"
        DOCKER_PARAMS="$DOCKER_PARAMS --runtime $RUNTIME"
    fi

    if [ "$RUN_UI" == "1" ] ; then
        DOCKER_PARAMS="$DOCKER_PARAMS -e DISPLAY=${DISPLAY-:0} -e QT_X11_NO_MITSHM=1"
    fi

    if [ "$SKIP_PRIVILEGED" == "0" -a "$NEED_PRIVILEGED" == "1" ] ; then
        log INFO "-- Privileged mode required to run, enabling..."
        DOCKER_PARAMS="$DOCKER_PARAMS --privileged"
    elif [ "$SKIP_PRIVILEGED" == "1" -a "$NEED_PRIVILEGED" == "1" ] ; then
        log WARN "-- Need privileged mode, however privileged mode is disabled by user, some features might not work properly."
    else
        log DEBUG "-- Privileged mode is not required"
    fi

    if [[ $EUID -ne 0 ]]; then
        if [ ! -x "$(which $DOCKER_CMD)" -o ! -w "/var/run/docker.sock" ] || [[ "$DOCKER_PARAMS" != *"--privileged"* ]] ; then
            log WARN "-- Need sudo to run docker"
            DOCKER_CMD="sudo $DOCKER_CMD"
        else
            log DEBUG "-- sudo not needed to run $DOCKER_CMD"
        fi
    fi

    if [ -n "$XDG_RUNTIME_DIR" ] ; then
        DOCKER_MNT="$DOCKER_MNT -v $XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR"
    fi

    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ] ; then
        DOCKER_PARAMS="$DOCKER_PARAMS -e DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
    fi

    # operating mode
    if [ "$DOCKER_DAEMON" == "0" ] ; then
        log INFO "-- Foreground enabled"
        DOCKER_PARAMS="${DOCKER_PARAMS} --rm"
        
        if [ "$USE_IT" == "1" ] ; then
            DOCKER_PARAMS="${DOCKER_PARAMS} -it"
        fi
    else
        log INFO "-- Running docker in daemon mode"
        DOCKER_PARAMS="$DOCKER_PARAMS -d --restart unless-stopped"
    fi

    # expose ports
    DOCKER_PORTS=

    if [ "$NO_EXPOSE" == "0" ] ; then
        # TODO: Configure ports within docker ?
        if [ "$ENABLE_MQTT" == "1" -a -n "$MQTT_PORT" -a "$MQTT_PORT" -gt "0" ] ; then
            DOCKER_PORTS="$DOCKER_PORTS -p ${MQTT_PORT}:1883"
            log DEBUG "-- Exposing MQTT at $MQTT_PORT"
        fi
        if [ -n "$API_PORT" -a "$API_PORT" -gt "0" ] ; then
            DOCKER_PORTS="$DOCKER_PORTS -p ${API_PORT}:${INTERNAL_API_PORT}"
            log DEBUG "-- Exposing API at $API_PORT"
        fi
        if [ -n "$RTSP_PORT" -a "$RTSP_PORT" -gt "0" ] ; then
            DOCKER_PORTS="$DOCKER_PORTS -p ${RTSP_PORT}:8554"
            log DEBUG "-- Exposing RTSP at $RTSP_PORT"
        fi
        if [ -n "$UI_PORT" -a "$UI_PORT" -gt "0" ] ; then
            DOCKER_PORTS="$DOCKER_PORTS -p ${UI_PORT}:8889"
            log DEBUG "-- Exposing UI at $UI_PORT"
        fi
        if [ -n "$UI_DISCOVERY_PORT" -a "$UI_DISCOVERY_PORT" -gt "0" ] ; then
            DOCKER_PORTS="$DOCKER_PORTS -p ${UI_DISCOVERY_PORT}:12349/udp"
            log DEBUG "-- Exposing CVEDIA-RT discovery at $UI_DISCOVERY_PORT"
        fi
        if [ "$USE_NXW_PLUGIN" == "1" -a -n "$NXW_PORT" -a "$NXW_PORT" -gt "0" ] ; then
            DOCKER_PORTS="$DOCKER_PORTS -p ${NXW_PORT}:7001/tcp -p ${NXW_PORT}:7001/udp"
            log DEBUG "-- Exposing VMS: $NXW_TAG at $NXW_PORT"
        fi
    else
        log DEBUG "-- NO_EXPOSE enabled; Not exposing any ports"
    fi

    # tracy is not affected by NO_EXPOSE
    if [ -n "$TRACY_PORT" ] ; then
        DOCKER_PORTS="$DOCKER_PORTS -p ${TRACY_PORT}:8086/tcp -p ${TRACY_PORT}:8086/udp"
        log DEBUG "-- Exposing tracy at ${TRACY_PORT}"
    fi

    RUN_DEBUG=${RUN_DEBUG-0}

    if [ "$RUN_DEBUG" == "1" ] ; then
        log DEBUG "-- Debug mode enabled, setting up..."
        
        CORE_DUMP_PATH=${CORE_DUMP_PATH-/tmp}
        CORE_DUMP_PERSIST=${CORE_DUMP_PERSIST-1}
        CORE_PATTERN_FILE=${CORE_PATTERN_FILE-/proc/sys/kernel/core_pattern}
        
        if [ ! -f "$CORE_PATTERN_FILE" ] ; then
            log ERROR "-- Expected core pattern file: $CORE_PATTERN_FILE not found."
            log ERROR "-- If your distro uses a different path fore core dumps, please define it using CORE_PATTERN_FILE env variable."
            check_exit 1
        fi
        
        if [ "$DRY_RUN" == "0" ] ; then
            if [[ $EUID -ne 0 ]]; then
                log INFO "-- Requesting core dump patterns using sudo"
            fi
            
            echo "${CORE_DUMP_PATH}/core.%e.%p" | sudo tee $CORE_PATTERN_FILE &> /dev/null
            check_exit $? "Failed to set $CORE_PATTERN_FILE"
            cat $CORE_PATTERN_FILE
        else
            log DEBUG "-- Dry run enabled, not setting core dump patterns"
        fi

        DOCKER_PARAMS="$DOCKER_PARAMS -e CORE_DUMP_PERSIST=$CORE_DUMP_PERSIST -e CORE_DUMP_PATH=${CORE_DUMP_PATH} --init --ulimit core=-1"
        
        if [ "$CORE_DUMP_PERSIST" == "1" ] ; then
            DOCKER_PARAMS="$DOCKER_PARAMS -v ${CORE_DUMP_PATH}:${CORE_DUMP_PATH}"
        fi

        log INFO "-- Core dumps will be available at: ${CORE_DUMP_PATH}"
    fi

    if [ -z "$GST_PLUGIN_PATH" ] ; then
        GST_PLUGIN_PATH=/usr/lib/${ARCH}-linux-gnu/gstreamer-1.0
    else
        log DEBUG "-- Adding user defined GST_PLUGIN_PATH"
        
        _IFS=$IFS
        IFS=":"
        K=0
        x=
        
        # patch and validate local paths to work within docker
        for p in $GST_PLUGIN_PATH; do
            p=$(realpath "$p")
            
            if [ -n "$p" -a -d "$p" ] ; then
                n=/opt/gst-user-plugins/${K}
                if [ -z "${x}" ] ; then
                    x=${n}
                else
                    x=${x}:${n}
                fi

                DOCKER_PARAMS="$DOCKER_PARAMS -v ${p}:${n}:ro"
                log DEBUG "-- Mapped: ${p} to ${n}"
                K=$((K + 1))
            elif [ -n "$p" ] ; then
                log WARN "-- Skipping invalid GST_PLUGIN_PATH: $p"
            fi
        done
        
        IFS=$_IFS
        
        if [ -n "${x}" ] ; then
            x=${x}:
        fi

        GST_PLUGIN_PATH=${x}/usr/lib/${ARCH}-linux-gnu/gstreamer-1.0
    fi

    if [ -n "$CUSTOM_LIB_PATH" ] ; then
        log DEBUG "-- Adding user defined library paths"
        
        _IFS=$IFS
        IFS=":"
        K=0
        x=
        
        # patch and validate local paths to work within docker
        for p in $CUSTOM_LIB_PATH; do
            p=$(realpath $p)
            
            if [ -n "$p" -a -d "$p" ] ; then
                n=/opt/custom-lib/${K}
                if [ -z "${x}" ] ; then
                    x=${n}
                else
                    x=${x}:${n}
                fi

                DOCKER_PARAMS="$DOCKER_PARAMS -v ${p}:${n}:ro"
                log DEBUG "-- Mapped: ${p} to ${n}"
                K=$((K + 1))
            elif [ -n "$p" ] ; then
                log WARN "-- Skipping invalid CUSTOM_LIB_PATH: $p"
            fi
        done
        
        IFS=$_IFS
        CUSTOM_LIB_PATH=${x}
    fi
    
    if [ "$USE_NXW_PLUGIN" == "1" ] ; then
        if [ "$USER_DEFINED_TAG" == "0" ] ; then
            TAG=${TAG}-${NXW_TAG}
        fi

        if [ "$SKIP_NXW_HOST" == "0" ] ; then
            if [[ "$DOCKER_PARAMS" != *"--network host"* ]] ; then
                DOCKER_PARAMS="$DOCKER_PARAMS --network host"
            fi
        fi
    fi

    if [ "$SKIP_ROCKCHIP" == "0" -a "$IS_ROCKCHIP" == "1" ] ; then
        # npu governor - WARN: as of now, there's no auto scaling governor in e25 platform
        NPU_GOVERNOR=${NPU_GOVERNOR-performance}
        # gpu governor
        GPU_GOVERNOR=${GPU_GOVERNOR-simple_ondemand}
        # dmc governor
        DMC_GOVERNOR=${DMC_GOVERNOR-performance}
        
        if [ -e "/sys/class/devfreq" ] ; then
            # set governors
            
            #shellcheck disable=SC2010
            if [ "$(ls --color=never -1 /sys/class/devfreq/ 2>/dev/null | grep -c \.npu)" -gt "0" -a -n "$NPU_GOVERNOR" ] ; then
                log INFO "Setting NPU governor to $NPU_GOVERNOR"
                #shellcheck disable=SC2086
                echo $NPU_GOVERNOR > /sys/class/devfreq/*.npu/governor
            fi
            
            #shellcheck disable=SC2010
            if [ "$(ls --color=never -1 /sys/class/devfreq/ 2>/dev/null | grep -c \.gpu)" -gt "0" -a -n "$GPU_GOVERNOR" ] ; then
                log INFO "Setting GPU governor to $GPU_GOVERNOR"
                #shellcheck disable=SC2086
                echo $GPU_GOVERNOR > /sys/class/devfreq/*.gpu/governor
            fi
        fi

        if [ -e "/sys/devices/platform/dmc/devfreq/dmc/governor" -a -n "$DMC_GOVERNOR" ] ; then
            log INFO "Setting DMC governor to $DMC_GOVERNOR"
            #shellcheck disable=SC2086
            echo $DMC_GOVERNOR > /sys/devices/platform/dmc/devfreq/dmc/governor
        fi
    fi

    if [ "$NO_LOG" == "1" ] ; then
        if [[ "$DOCKER_PARAMS" != *"--log-driver"* ]] ; then
            DOCKER_PARAMS="$DOCKER_PARAMS --log-driver none"
        fi
    fi

    # append env to params if they're set
    for i in TZ CRT_NICE CRT_TASKSET RUN_UI RUN_DEBUG MM_OPT PLUGIN_BLACKLIST RUN_STANDALONE GST_DEBUG IS_CMD IS_JETSON IS_QUALCOMM IS_HAILO IS_ROCKCHIP SKIP_QUALCOMM SKIP_ROCKCHIP SKIP_HAILO SKIP_LD_PRELOAD USE_NXW_PLUGIN QUICK_START NXW_TAG GST_PLUGIN_PATH CUSTOM_LIB_PATH; do
        if [ -n "${!i}" ] ; then
            DOCKER_PARAMS="$DOCKER_PARAMS -e ${i}=${!i}"
        fi
    done

    # common env variables
    read -r -d '' DOCKER_PARAMS << EOF
$DOCKER_PARAMS \
    -e LIBGL_DEBUG=verbose \
    -e TRACY_NO_INVARIANT_CHECK=1 \
    -e RUN_MQTT=$ENABLE_MQTT \
    -e ADSP_LIBRARY_PATH=/opt/lib \
    -e REDIST_VERSION=${REDIST_VERSION-unknown}
EOF

}

run_if_exists() {
    if [ -z "$1" ] ; then
        log ERROR "No filename set, aborting"
        return
    fi

    local must_run=${2:-0}
    local fn="$1"
    local ran=0
    
    if [ -n "$USE_CONFIG" -a "$USE_CONFIG" == "1" ]; then
        if [ -f "${CONFIG_MOUNT}/${fn}" ] ; then
            log INFO "-- Running ${fn} from config..."
            cp ${CONFIG_MOUNT}/${fn} /tmp/${fn} && chmod +x /tmp/${fn} && /tmp/${fn}
            RT=$?
            if [ "$RT" != "0" ] ; then
                log ERROR "-- Error running: ${fn}"
            fi
            rm -f /tmp/${fn} &> /dev/null
            ran=1
        else
            log DEBUG "-- ${CONFIG_MOUNT}/${fn} doesn't exist, skipping"
        fi
    fi

    if [ "$must_run" == "1" -a "$ran" == "0" ] ; then
        log ERROR "-- Script: ${fn} didn't run properly, aborting"
        kill $PID
        exit 1
    fi
}

extract_assets() {
    if [ -z "$1" ]  ; then
        TARGET=solutions
    else
        TARGET=$1
    fi

    if [ -d "${CRT_PATH}/${TARGET}" ] ; then
        log WARN "-- ${TARGET} folder already exists at ${CRT_PATH}, your files may be overwritten"
        log WARN "-- Press CTRL+C to abort, waiting 10 seconds..."
        sleep 10
    fi

    mkdir ${CRT_PATH}/${TARGET} &> /dev/null

    NO_EXPOSE=1
    USE_RUNC=1
    RUN_UI=0

    resolve_docker

    read -r -d '' cmd << EOF
$DOCKER_CMD run --rm --runtime runc \
    --entrypoint /usr/bin/rsync -v ${CRT_PATH}/${TARGET}:/${TARGET} \
    $TAG -av /opt/cvedia-rt/${TARGET}/ /${TARGET}/
EOF

    log INFO "-- Running: ${cmd}..."
    set -x
    $cmd
    RT=$?
    set +x

    if [ "$RT" != "0" ] ; then
        log ERROR "Failed to copy solutions assets"
        exit $RT
    fi

    # fix permissions
    if [[ $EUID -ne 0 ]]; then
        log INFO "-- Fixing permissions..."
        sudo chown -R $USER:$USER ${TARGET}
    fi

    log INFO "-- Copied project assets to ${CRT_PATH}/${TARGET}, next time you call run.sh they will be automatically mounted"
    log INFO "-- To reset this instance to it's original state you can simply delete the ${TARGET} folder."
}