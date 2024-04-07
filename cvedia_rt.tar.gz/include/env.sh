#!/bin/bash

declare -x REDIST_VERSION=2023.7.22

declare -x CRT_PATH=${CRT_PATH-$(realpath $(dirname $(realpath $BASH_SOURCE))/../)}
declare -x NO_COLOR=${NO_COLOR-0}
declare -x NO_CACHE=${NO_CACHE-0}
declare -x HOSTNAME="${HOSTNAME-$(hostname)}"
declare -x LOG_BASE=$(realpath "${LOG_BASE-${CRT_PATH}/log}")
declare -x LOG_FN="${LOG_BASE}/cvedia-rt-$(date +%s%N).log"

mkdir -p "$LOG_BASE" &> /dev/null

# first pass
ARCH=${ARCH-$(uname -p)}

# second pass
if [ -z "$ARCH" -o "$ARCH" == "unknown" ] ; then
    if [ -n "$(command -v lscpu)" ] ; then
        x=$(lscpu | head -n1 | rev | cut -d' ' -f1 | rev)
    fi

    if [ -z "$x" -a -n "$(command -v uname)" ] ; then
        x=$(uname -m)
    fi

    if [ -z "$x" -o "$x" == "unknown" ]; then
        bits=0
        is_arm=0
        
        if [ -n "$(command -v getconf)" ] ; then
            bits=$(getconf LONG_BIT)
        fi
        
        if [ -f "/proc/cpuinfo" ] ; then
            is_arm=$(grep -ci "arm" /proc/cpuinfo)
        fi

        if [ "$is_arm" -gt "0" -a "$bits" == "64" ] ; then
            ARCH=aarch64
        elif [ "$is_arm" -gt "0" ] ; then # 32 bit arm
            ARCH=armv7l
        else # not arm
            ARCH=x86_64
        fi
    fi
    
    ARCH=$x
fi

# export
declare -x ARCH=${ARCH}