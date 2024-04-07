#!/bin/bash

# TODO: Move this logic to run.sh

#shellcheck disable=SC1091
source $(dirname $(realpath $BASH_SOURCE))/include/common.sh

if [[ $EUID -ne 0 ]]; then
    log ERROR "-- Please run this script as root or sudo $0"    
    exit 1
fi

if [ -z "$NO_LOG" -a -z "$IS_WRAPPED" ] ; then
    export IS_WRAPPED=1
    export LOG_FN="${LOG_BASE}/test-$(date +%s%N).log"
    
    log INFO "-- Logging runner to $LOG_FN"
    set -o pipefail
    $0 $@ | tee $LOG_FN
    RT=$?
    log INFO "-- Test log saved to: $LOG_FN"
    exit $RT
fi

VERSION="1.0.0"
DOCKER_CMD="docker"
ARCH=${ARCH:-$(uname -p)}
ERRORS=0

log INFO "-- CVEDIA-RT Tester v$VERSION"
log INFO "-- ARCH: $ARCH"

log INFO "-- Kernel"
cat /proc/version

log INFO "-- CPU Info"
cat /proc/cpuinfo

log INFO "-- Memory Info"
cat /proc/meminfo

if [ "$ARCH" = "aarch64" ] ; then
    if [ -f "/etc/nv_tegra_release" ] ; then
        log INFO "-- Tegra full release: $(cat /etc/nv_tegra_release)"
    else
        log ERROR "-- No tegra release tag found!"
        ERRORS=$((ERRORS + 1))
    fi
fi

log INFO "-- Testing X11 depends"

if [ -n "$(command -v xhost)" ] ; then
    log INFO "-- XHOST available"
else
    log WARN "-- XHOST missing, UI might not work"
fi

if [ -n "$(command -v xhost)" ] ; then
    log INFO "-- XHOST available"
else
    log WARN "-- XHOST missing, UI might not work"
fi

if [ -n "$(command -v glxinfo)" ] ; then
    log INFO "-- GLXINFO available"
    if [ -z "$DISPLAY" ] ; then
        log WARN "-- DISPLAY not set, assuming :0"
        DISPLAY=:0 glxinfo
    else
        glxinfo
    fi
else
    log WARN "-- GLXINFO missing, skipping GLX checks"
fi

if [ ! -d "/tmp/.X11-unix" ] ; then
    log WARN "-- No X11 session running, UI might not work"
else
    log INFO "-- X11 session found"
    GUESS="$(w | grep xdm | cut -d' ' -f1 | head -n1)"
    
    if [ -n "$GUESS" ] ; then
        log INFO "-- Guessed xdm user to $GUESS"
    else
        log WARN "-- Failed to find xdm user"
    fi
fi

if [ -n "$(command -v df)" ] ; then
    log INFO "-- Space check"
    df -h /var/lib/docker
fi

log INFO "-- Inspecting docker"

if [ -n "$(command -v $DOCKER_CMD)" ] ; then
    if [ ! -e "/var/run/docker.sock" ] ; then
        log ERROR "-- /var/run/docker.sock not found, is docker daemon running?"
        ERRORS=$((ERRORS + 1))
    fi

    log INFO "-- Docker version"
    $DOCKER_CMD version
    RT=$?
    if [ "$RT" != "0" ] ; then
        ERRORS=$((ERRORS + 1))
    fi
    
    log INFO "-- Docker info"
    $DOCKER_CMD info
    RT=$?
    if [ "$RT" != "0" ] ; then
        ERRORS=$((ERRORS + 1))
    fi

    if [ "$($DOCKER_CMD info | grep Runtimes | grep -ic nvidia)" == "0" ] ; then
        log WARN "-- Docker NVIDIA runtime not installed, you can still run CVEDIA-RT in CPU, performance might be poor."
        ERRORS=$((ERRORS + 1))

        if [ -f "/usr/bin/nvidia-container-runtime" ] ; then
            log ERROR "-- NVIDIA Runtime binary exists, but not linked to docker daemon, possible fix:"
            log ERROR "-- https://github.com/NVIDIA/nvidia-docker/wiki/NVIDIA-Container-Runtime-on-Jetson#docker-info-doesnt-show-the-nvidia-runtime"
        fi
    else
        log INFO "-- Docker NVIDIA runtime found"
    fi
else
    log ERROR "-- Docker command: $DOCKER_CMD not found!"
    ERRORS=$((ERRORS + 1))
fi

log INFO "-- Listing nvidia packages"
dpkg -l | grep -i nvidia

log INFO "-- Testing nvidia container"

if [ -n "$(command -v nvidia-container-cli)" ] ; then
    nvidia-container-cli -k -d /dev/tty info
    RT=$?
    if [ "$RT" == "0" ] ; then
        log INFO "-- Clean exit"
    else
        log ERROR "-- Unclean exit, code: $RT"
        ERRORS=$((ERRORS + 1))
    fi
else
    log WARN "-- nvidia-container-cli binary not found"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ARCH" = "x86_64" ] ; then
    if [ -n "$(command -v nvidia-smi)" ] ; then
        log INFO "-- NVIDIA-SMI found"
        nvidia-smi
    else
        log INFO "-- NVIDIA-SMI not found"
    fi
fi

if [ "$ERRORS" -gt "0" ] ; then
    log ERROR "-- $ERRORS checks failed"
else
    log INFO "-- All checks completed"
fi
