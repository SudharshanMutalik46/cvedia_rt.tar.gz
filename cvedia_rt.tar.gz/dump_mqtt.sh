#!/bin/bash

if [ -z "$(command -v mosquitto_sub)" ] ; then
    echo "-- ERROR: Mosquitto clients are not installed, run:"
    echo "apt install mosquitto-clients"
    exit 1
fi

mosquitto_sub -d -h ${HOST-127.0.0.1} -t ${TOPIC-test}
