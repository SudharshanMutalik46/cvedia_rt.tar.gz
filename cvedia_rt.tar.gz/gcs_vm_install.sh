#!/bin/bash

declare -x NO_COLOR=${NO_COLOR:-0}
declare -x HOSTNAME="${HOSTNAME:-$(hostname)}"
declare -x ARCH=${ARCH-$(uname -m)}

GCSVMI_VERSION=2023.02.24
DESKTOP=${DESKTOP-0}
SKIP_TEST=${SKIP_TEST-0}
SKIP_DRIVER=${SKIP_DRIVER-0}
SKIP_DOCKER=${SKIP_DOCKER-0}
SKIP_NVIDIA_DOCKER=${SKIP_NVIDIA_DOCKER-0}
SKIP_EXTRACT=${SKIP_EXTRACT-0}
SKIP_AUTOUPDATE=${SKIP_AUTOUPDATE-0}
DRIVER_URL=${DRIVER_URL-https://us.download.nvidia.com/tesla/525.60.13/NVIDIA-Linux-x86_64-525.60.13.run}
CVEDIA_BIN="https://bin.cvedia.com"
GCS_XORG_BASE="${CVEDIA_BIN}/gcs_xorg_base.conf"
RELEASE=${RELEASE-2023.1.0}
XUSR=${SUDO_USER:-$USER}
XHOME=$(getent passwd ${XUSR} | cut -d: -f6)
CVEDIA_INSTALL_DIR=${CVEDIA_INSTALL_DIR-/opt/cvedia-rt}
DRY_RUN=${DRY_RUN-0}
TEST_IMAGE=${TEST_IMAGE-nvidia/cuda:11.0.3-base-ubuntu20.04}

log () {
    if [ "$NO_COLOR" = "1" ] ; then
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

### ARG PARSE #################################################################

PROGNAME=$0

#shellcheck disable=SC2120
usage () {
	if [ -n "$*" ]; then
		message "usage error: $*"
	fi
	cat <<EOF
Usage: $PROGNAME [OPTIONS ...] [[-- DOCKER PARAMS ... [-- RUNTIME PARAMS ...]]]

This script automatically installs NVIDIA drivers, docker and nvidia-docker and pre-configures CVEDIA-RT to run either a daemon or desktop application.

Options:
    -h, --help: Shows this message and exit
    
    -d, --desktop: Install desktop environment and drivers
    -r, --release <release>: CVEDIA-RT release to install (default: $RELEASE)
    -i, --install <install path>: CVEDIA-RT install path (default: $CVEDIA_INSTALL_DIR)
    -D, --driver <driver url>: NVIDIA driver url (default: $DRIVER_URL)

    -Z, --dry_run: Do not run the application, just print the commands that would be executed

    -T, --test_image <test image>: NVIDIA test docker image (default: $TEST_IMAGE) -- only effective when not using --skip_test

    --skip_test: Do not run NVIDIA test docker
    --skip_driver: Do not install NVIDIA drivers
    --skip_docker: Do not install docker
    --skip_nvidia_docker: Do not install nvidia-docker
    --skip_extract: Do not extract CVEDIA-RT projects
    --skip_autoupdate: Do not disable unattended auto updates -- this may break your drivers if nvidia driver is auto updated

    -v, --version: Prints version and exit

EOF
}

ARGS=$(getopt --options +h,d,r:,i:,Z,v,D:,T: \
	--long help,desktop,release:,install:,dry_run,dry-run,skip_test,skip-test,version,driver:,skip_driver,skip-driver,skip_docker,skip-docker,skip_nvidia_docker,skip-nvidia-docker,skip-extract,skip_extract,skip_autoupdate,skip-autoupdate,test_image:,test-image: \
	--name "$PROGNAME" -- "$@")
GETOPT_STATUS=$?

if [ $GETOPT_STATUS -ne 0 ]; then
	error "internal error; getopt exited with status $GETOPT_STATUS"
	exit 6
fi

eval set -- "$ARGS"

if [ "$#" != 0 ] ; then
    X=0
    
    while :; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -d|--desktop)
                declare -x DESKTOP=1
                ;;
            -r|--release)
                declare -x RELEASE=$1
                shift
                ;;
            -i|--install)
                declare -x CVEDIA_INSTALL_DIR=$1
                shift
                ;;
            
            --skip_test|--skip-test)
                declare -x SKIP_TEST=1
                ;;
            --skip_driver|--skip-driver)
                declare -x SKIP_DRIVER=1
                ;;
            --skip_docker|--skip-docker)
                declare -x SKIP_DOCKER=1
                ;;
            --skip_nvidia_docker|--skip-nvidia-docker)
                declare -x SKIP_NVIDIA_DOCKER=1
                ;;
            --skip_extract|--skip-extract)
                declare -x SKIP_EXTRACT=1
                ;;
            --skip_autoupdate|--skip-autoupdate)
                declare -x SKIP_AUTOUPDATE=1
                ;;
            -T|--test_image|--test-image)
                declare -x TEST_IMAGE=$1
                shift
                ;;
            -D|--driver)
                declare -x DRIVER_URL=$1
                shift
                ;;

            -Z|--dry_run|--dry-run) declare -x DRY_RUN=1 ;;

            -v|--version)
                log INFO "GCS VM Install v$GCSVMI_VERSION"
                exit 0 ;;
            
            --) shift; break ;;
            
            *) echo "Unknown option \"$1\" aborting"; exit 6 ;;
        esac
        shift
    done
fi

###############################################################################

log INFO "-- GCS VM Install: $GCSVMI_VERSION"

for i in DESKTOP SKIP_TEST DRIVER_URL CVEDIA_BIN GCS_XORG_BASE RELEASE XUSR XHOME CVEDIA_INSTALL_DIR TEST_IMAGE; do
    log DEBUG "-- $i: ${!i}"
done

if [ "$EUID" -ne "0" ] ; then
    log ERROR "-- This script must be run as root, eg: sudo $0"
    exit 87
fi

if [ -z "$SUDO_USER" ] ; then
    log WARN "-- Not running with sudo, desktop session may not work. Try running this script like: sudo $0"
    log WARN "-- Waiting 5 seconds..."
    sleep 5
fi

if [ "$DRY_RUN" -eq "1" ] ; then
    log INFO "-- Dry run enabled"
    exit 0
fi

log INFO "-- Updating cache..."
apt update
check_exit $? "Error updating apt cache"

if [ "$DESKTOP" -eq "1" ] ; then
	log INFO "-- Installing ubuntu desktop..."
	apt install ubuntu-desktop x11vnc -y
    check_exit $? "Error installing ubuntu desktop / x11vnc"
fi

log INFO "-- Installing dependencies..."
apt install build-essential wget screen tmux curl pkg-config libglvnd-dev ntp ntpdate -y
check_exit $? "Error installing dependencies"

if [ "$SKIP_DRIVER" -eq "0" ] ; then
    log DEBUG "-- Fetching driver from: ${DRIVER_URL}..."
    curl $DRIVER_URL -o driver.run
    check_exit $? "Error downloading NVIDIA driver"

    log INFO "-- Installing NVIDIA driver..."
    sh ./driver.run -s
    check_exit $? "Error installing NVIDIA driver"
    rm -f driver.run &> /dev/null
else
    log WARN "-- Skipping nvidia driver install"
fi

log INFO "-- Testing nvidia-smi..."
nvidia-smi
check_exit $? "Error testing nvidia-smi"

if [ "$SKIP_DOCKER" -eq "0" ] ; then
    log INFO "-- Installing docker..."
    curl -fsSL https://get.docker.com | sh
    check_exit $? "Error installing docker"

    systemctl --now enable docker
    systemctl restart docker
else
    log WARN "-- Skipping docker install"
fi

if [ "$SKIP_NVIDIA_DOCKER" -eq "0" ] ; then
    log INFO "-- Installing nvidia docker..."
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
        && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    apt-get update && apt-get install -y nvidia-docker2
    check_exit $? "Error installing nvidia docker"
    systemctl restart docker
    check_exit $? "Error restarting docker"
else
    log WARN "-- Skipping nvidia docker install"
fi

if [ "$SKIP_TEST" -eq "0" ] ; then
    log INFO "-- Testing nvidia docker with image $TEST_IMAGE" 
    docker run --rm --gpus all $TEST_IMAGE nvidia-smi
    check_exit $? "Error testing nvidia docker"
    log INFO "-- Cleanup"
    docker rmi $TEST_IMAGE
else
    log WARN "-- Skipping nvidia docker test"
fi

log INFO "-- Downloading CVEDIA-RT release: ${RELEASE}..."
mkdir ${CVEDIA_INSTALL_DIR} -p &> /dev/null
cd ${CVEDIA_INSTALL_DIR}
curl -fsSL ${CVEDIA_BIN}/${RELEASE}/Linux-${RELEASE}.tar.gz | tar -xzv
check_exit $? "Failed to download / extract CVEDIA-RT release: ${RELEASE}"

if [ -n "$DOCKER_LOGIN_CMD" ]; then
    log INFO "-- Logging into docker registry..."
    $DOCKER_LOGIN_CMD
    check_exit $? "Error logging into docker registry"
fi

if [ "$SKIP_EXTRACT" -eq "0" ] ; then
    log INFO "-- Extracting projects..."
    bash -c ./extract_projects.sh
    check_exit $? "Failed to extract projects"

    if [ -n "$SUDO_USER" -a "$SUDO_USER" != "root" ] ; then
        log DEBUG "-- Fixing permissions"
        chown -R $SUDO_USER:$SUDO_USER .
    fi
else
    log WARN "-- Skipping project extraction"
fi

if [ "$SKIP_AUTOUPDATE" -eq "0" ] ; then
    log INFO "-- Disabling unattended auto updates"
    if [ -f "/etc/apt/apt.conf.d/20auto-upgrades" ] ; then
        sed -i 's/Unattended-Upgrade "1"/Unattended-Upgrade "0"/' /etc/apt/apt.conf.d/20auto-upgrades
    else
        log ERROR "-- Unable to find auto-upgrade apt config file, skipping"
    fi
else
    log WARN "-- Skip autoupdate disable"
fi

if [ "$DESKTOP" -eq "1" ] ; then
    log INFO "-- Configuring xorg..."
    curl -fsSL ${GCS_XORG_BASE} -o /etc/X11/xorg.conf
    check_exit $? "Error fetching xorg base config from: ${GCS_XORG_BASE}"
    XUSR=${SUDO_USER-$USER}
    
    log INFO "-- Patching xorg to autostart with user: ${XUSR}..."
    if [ -f "/etc/gdm3/custom.conf" ] ; then
        sed -i "s/^#  AutomaticLoginEnable.*/AutomaticLoginEnable=true\nAutomaticLogin=${XUSR}/" /etc/gdm3/custom.conf
        check_exit $? "Error patching gdm3 config"
        log INFO "-- Restarting GDM3..."
        /etc/init.d/gdm3 restart
    else
        log WARN "-- No gdm3 /etc/gdm3/custom.conf found"
    fi
fi

log INFO "-- Setup has been completed"

if [ "$DESKTOP" -eq "1" ] ; then
    log WARN "-- You have enabled destkop installation"
    log INFO "-- To access via x11vnc:"
    log INFO "--    1. You should set a password for ${XUSR}, if you haven't yet, run: passwd $XUSR"
    log INFO "--    2. Run x11vnc as ${XUSR} then open connect using a vnc client on port 5900"
    log INFO "-- To run CVEDIA-RT without ui, run with RUN_UI=0"
else
    log WARN "-- Desktop install wasn't enabled, CVEDIA-RT, you should run CVEDIA-RT with --remote or --headless"
fi

log INFO "-- CVEDIA-RT has been installed at ${CVEDIA_INSTALL_DIR}, to start it run:"
log INFO "-- cd ${CVEDIA_INSTALL_DIR} && ./run.sh"
log INFO "-- For all running options, cd ${CVEDIA_INSTALL_DIR} && ./run.sh --help"
log INFO "-- CVEDIA-RT documentation can be found at: https://docs.cvedia.com"

echo "-- Completed"
exit 0