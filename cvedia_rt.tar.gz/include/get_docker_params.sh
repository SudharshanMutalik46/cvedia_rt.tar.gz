#!/bin/bash

#shellcheck disable=SC1091
source $(dirname $(realpath $BASH_SOURCE))/common.sh

if [ -z "$1" ] ; then
    log INFO "-- Usage: $0 <path/to/env/to/save>"
    exit 1
fi

OEFN="$1"

resolve_docker
echo "#!/bin/sh" > $OEFN

for i in DOCKER_CMD DOCKER_MNT DOCKER_PARAMS TAG; do
    log DEBUG "-- ${i}: ${!i}"
    echo "export ${i}=\"${!i}\"" >> $OEFN
done

exit 0