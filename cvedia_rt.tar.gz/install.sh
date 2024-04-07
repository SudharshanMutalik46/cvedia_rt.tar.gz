#!/bin/bash

#shellcheck disable=SC1091
source $(dirname $(realpath $BASH_SOURCE))/include/common.sh

CHANGES=0
CHECK_X11=0
AUTOMATIC_PATCH=0
SKIP_XORG_CHECKS=0
CHECK_DOCKER=${CHECK_DOCKER:-1}
TFN=$(mktemp)

if [[ $EUID -ne 0 ]]; then
    log ERROR "-- You need to run this script as root or sudo $0"
    exit 1
fi

log INFO "-- If you're planning to run CVEDIA-RT user interface we will have to check X11 compatibility."
log INFO "-- Perform X11 check? [y/n] "

while true; do
    read -rp ">>> " yn
    case $yn in
        [Yy]* ) CHECK_X11=1;break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [ "$CHECK_X11" == "1" ] ; then
    log INFO "-- Should we automatically modify files ? (backups will be made)"
    log INFO "-- Anwsering 'no' will display what has to be changed without changing anything."
    log INFO "-- [y/n]"
    
    while true; do
        read -rp ">>> " yn
        case $yn in
            [Yy]* ) AUTOMATIC_PATCH=1;break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

    if [ -f "patches/${ARCH}/etc/X11/xorg.conf" ] ; then
        log INFO "-- Checking Xorg..."
        if [ -z "$(command -v Xorg)" ] ; then
            log ERROR "-- Xorg is not installed, please install it before running this script."
            exit 1
        fi

        log INFO "-- Checking X11 config..."
        if [ -z "$XCONF" ] ; then
            if [ -n "$XORGCONFIG" -a -f "$XORGCONFIG" ]  ; then
                XCONF="$XORGCONFIG"
            else
                for f in /etc/X11/xorg.conf /etc/xorg.conf /usr/etc/X11/xorg.conf /usr/lib/X11/xorg.conf; do
                    if [ -f "$f" ] ; then
                        XCONF="${f}"
                        break
                    fi
                done
            fi

            if [ -z "$XCONF" ]; then
                if [ -d "/etc/X11" ] ; then
                    log DEBUG "-- No X11 config found, using default path"
                    XCONF=/etc/X11/xorg.conf
                else
                    log ERROR "-- X11 install folder not found, please install X11 before running this script."
                    exit 1
                fi
            fi
        else
            log INFO "-- Using predefined XCONF: ${XCONF}"
        fi

        if [ ! -f "$XCONF" ] ; then
            log INFO "-- X11 config: ${XCONF} not found, if you're using a different path define XCONF to override the default."
            log INFO "-- This script can create a generic xorg config, should we do it?"
            log INFO "-- Anwsering 'yes' will generate a config at ${XCONF} and restart window manager"
            log INFO "-- Anwsering 'no' will abort install."
            log INFO "-- Anwsering 'skip' will skip xorg checks and assume you will deal with it later."
            log INFO "-- [y/n/s]"
            
            while true; do
                read -rp ">>> " yn
                case $yn in
                    [Yy]* )
                        log INFO "-- Generating generic xorg config..."
                        
                        if [ "$ARCH" = "aarch64" ] ; then
                            if [ -f "/etc/nv_tegra_release" ] ; then # is nvidia
                                log DEBUG "-- Detected nvidia jetson, using nvidia xorg config"
                                PFN=patches/${ARCH}/etc/X11/xorg_default_nvidia.conf
                            else # default
                                PFN=patches/${ARCH}/etc/X11/xorg_default.conf
                            fi
                        else
                            if [ -z "$(command -v nvidia-smi)" ] ; then
                                PFN=patches/${ARCH}/etc/X11/xorg_default.conf
                            else
                                log DEBUG "-- Detected nvidia-smi, using nvidia xorg config"
                                PFN=patches/${ARCH}/etc/X11/xorg_default_nvidia.conf
                            fi
                        fi

                        log DEBUG "-- Copying: $PFN to $XCONF"
                        cp -vf $PFN $XCONF
                        check_exit $? "Failed to copy $PFN to $XCONF"
                        SKIP_XORG_CHECKS=1
                        CHANGES=$((CHANGES + 1))
                        break;;

                    [Nn]* )
                        log INFO "-- Aborting"
                        exit 0;;

                    [Ss]* )
                        log INFO "-- Skipping xorg checks"
                        SKIP_XORG_CHECKS=1
                        break;;

                    * ) echo "Please answer yes, no or skip";;
                esac
            done
        fi
        
        if [ "$SKIP_XORG_CHECKS" == "0" ] ; then
            grep -o '^[^#]*' "$XCONF" > "$TFN"
            C0=$(grep -c 'Option "IndirectGLX" "on"' $TFN)
            C1=$(grep -c 'Option "AllowIndirectGLX" "on"' $TFN)

            if [ "$C0" == "1" -a "$C1" == "1" ] ; then
                log INFO "-- X11 config OK"
            else
                if [ "$AUTOMATIC_PATCH" == "1" ] ; then
                    log WARN "-- Creating xorg.conf backup..."
                    cp -v "${XCONF}" "${XCONF}.cvedia-$(date +%s%N)"
                    log WARN "-- Patching xorg.conf"
                    cat patches/${ARCH}/etc/X11/xorg.conf >> "$XCONF"
                    RT=$?
                    
                    if [ "$RT" != "0" ] ; then
                        log ERROR "-- Failed patching xorg.conf!"
                        exit 1
                    fi
                else
                    log WARN "-- Your $XCONF doesn't contain IndirectGLX and AllowIndirectGLX options, you should"
                    log WARN "-- add a new section called ServerFlags with this options, example:"
                    grep -o '^[^#]*' patches/${ARCH}/etc/X11/xorg.conf
                fi

                CHANGES=$((CHANGES + 1))
            fi
        fi
    else
        log DEBUG "-- No X11 patches available for arch: ${ARCH}"
    fi

    # nvidia jetson only (mostly)
    if [ "$ARCH" = "aarch64" ] ; then
        # check if there's a screen defined
        C0=$(grep -c 'Section "Screen"' $TFN)
        if [ "$C0" == "0" ] ; then
            log INFO "-- It looks like you don't have a screen defined at X11, if you don't have a real screen plugged in"
            log INFO "-- running the CVEDIA-RT UI might fail and / or X11 might start in a very low resolution."

            if [ "$AUTOMATIC_PATCH" == "1" ] ; then
                log INFO "-- If you apply this patch a default 1920x1080 screen will be added, this will work with / without a real screen."
                log INFO "-- Apply virtual screen patch? [y/n]"

                while true; do
                    read -rp ">>> " yn
                    case $yn in
                        [Yy]* )
                            log INFO "-- Creating backup..."
                            cp -v "${XCONF}" "${XCONF}.cvedia-$(date +%s%N)"
                            log INFO "-- Patching..."
                            cat patches/${ARCH}/etc/X11/xorg_virtual.conf >> "$XCONF"
                            CHANGES=$((CHANGES + 1))
                            break;;
                        [Nn]* ) break;;
                        * ) echo "Please answer yes or no.";;
                    esac
                done
            else
                log INFO "-- You can create a virtual screen by adding the following to your ${XORG}:"
                grep -o '^[^#]*' patches/${ARCH}/etc/X11/xorg_virtual.conf
                echo
            fi
        fi
    fi

    # check startx
    if [ -f "patches/${ARCH}/usr/bin/startx" ] ; then
        STARTX=${STARTX:-/usr/bin/startx}
        STARTX_PATCH=0
        
        log INFO "-- Checking startx @ $STARTX"
        
        if [ ! -f "$STARTX" ] ; then
            log WARN "-- No startx found at $STARTX"
            STARTX_PATCH=1
        else
            grep -o '^[^#]*' "$STARTX" > "$TFN"
            C0=$(grep -c '+iglx' $TFN)
            if [ "$C0" == "0" ] ; then
                STARTX_PATCH=1
            else
                log INFO "-- STARTX OK"
            fi
        fi

        if [ "$STARTX_PATCH" == "1" ] ; then
            if [ "$AUTOMATIC_PATCH" == "1" ] ; then
                log INFO "-- Creating backup..."
                XBAK="${STARTX}.cvedia-$(date +%s%N)"
                cp -v "${STARTX}" "$XBAK"
                chmod -x "$XBAK"
                log INFO "-- Patching STARTX..."
                sed -i -r 's/defaultserverargs=""/defaultserverargs="+iglx"/g' "${STARTX}"
            else
                log WARN "-- Your $STARTX needs to allow for indirect glx, this is one line change on defaultserverargs:"
                cat patches/${ARCH}/usr/bin/startx
                echo
            fi

            CHANGES=$((CHANGES + 1))
        fi
    else
        log DEBUG "-- No startx patches for arch: ${ARCH}"
    fi
    
    if [ -z "$(command -v lightdm)" ] ; then
        log WARN "-- lightdm not installed, skipping checks"
    else
        if [ -f "patches/${ARCH}/usr/share/lightdm/lightdm.conf.d/50-xserver-command.conf" ] ; then
            log INFO "-- Checking lightdm xserver service..."
            XSERVER_SERVICE=${XSERVER_SERVICE:-/usr/share/lightdm/lightdm.conf.d/50-xserver-command.conf}
            XSERVER_SERVICE_PATCH=0
            
            if [ ! -f "$XSERVER_SERVICE" ] ; then
                log WARN "-- XSERVER_SERVICE file: ${XSERVER_SERVICE} doesn't exist"
                XSERVER_SERVICE_PATCH=1
            else
                grep -o '^[^#]*' "$XSERVER_SERVICE" > "$TFN"
                C0=$(grep -c '+iglx' "$TFN")
                if [ "$C0" == "0" ] ; then
                    XSERVER_SERVICE_PATCH=1
                else
                    log INFO "-- Lightdm OK"
                fi
            fi

            if [ "$XSERVER_SERVICE_PATCH" == "1" ] ; then
                if [ "$AUTOMATIC_PATCH" == "1" ] ; then
                    log INFO "-- Creating backup"
                    cp -v "${XSERVER_SERVICE}" "${XSERVER_SERVICE}.cvedia-$(date +%s%N)"
                    log INFO "-- Patching Lightdm..."
                    cat patches/${ARCH}/usr/share/lightdm/lightdm.conf.d/50-xserver-command.conf > "${XSERVER_SERVICE}"
                else
                    log WARN "-- Your $XSERVER_SERVICE lightdm config needs to allow for indirect glx, example:"
                    cat patches/${ARCH}/usr/share/lightdm/lightdm.conf.d/50-xserver-command.conf
                    echo
                fi

                CHANGES=$((CHANGES + 1))
            fi
        else
            log DEBUG "-- No lightdm patches for arch: ${ARCH}"
        fi
    fi
fi

if [ "$CHECK_DOCKER" == "1" ] ; then
    log INFO "-- Checking docker..."
    if [ -z "$(command -v docker)" ] ; then
        log ERROR "-- Docker is not installed, please follow https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    log INFO "-- Docker binary found"
    
    if [ -z "$(command -v nvidia-docker)" ] ; then
        log WARN "-- NVIDIA docker is not installed"
        log WARN "-- CVEDIA-RT can run without nvidia docker directly on CPU, however, performance might be poor"
        log WARN "-- If this device has a NVIDIA GPU you should install NVIDIA docker following instructions at:"
        log WARN "-- https://github.com/NVIDIA/nvidia-docker"
    else
        log INFO "-- NVIDIA Docker detected"
    fi
fi

if [ "$CHANGES" -ge "1" ] ; then
    if [ "$AUTOMATIC_PATCH" == "1" ] ; then
        systemctl daemon-reload
        log WARN "-- $CHANGES changes were performed"
        
        if [ "$CHECK_X11" == "1" ] ; then
            log INFO "-- You should restart X11 or reboot the device to make sure changes are correctly applied."
        fi
    else
        log WARN "-- There's $CHANGES changes that need to be manually made."
        log WARN "-- Once you completed them, run:"
        log WARN "-- systemctl daemon-reload"
        log WARN "-- then restart X11 or reboot the device."
    fi
else
    log INFO "-- No changes need to be made, looks like you're ready to go!"
    log INFO "-- You're unable to start the application, run ./test.sh to generate a report for better support."
fi

exit 0