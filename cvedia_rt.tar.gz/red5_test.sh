#!/bin/bash

docker run -d --restart unless-stopped --name red5 -h red5 -p 1935:1935 -p 5080:5080 vimagick/red5
