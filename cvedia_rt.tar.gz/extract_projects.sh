#!/bin/bash

cd $(dirname $(realpath $BASH_SOURCE)) && ./run.sh -e $@
