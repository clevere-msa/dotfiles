#!/bin/bash

LC_USERNAME=$(echo ${LOGNAME} | tr "[:upper:]" "[:lower:]")
ARTIFACTORY_API_KEY=$(/home/$LC_USERNAME/bin/get_art_api_key.sh)
