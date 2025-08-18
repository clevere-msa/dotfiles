#!/bin/bash
LC_USERNAME=$(echo ${LOGNAME} | tr "[:upper:]" "[:lower:]")
cd "/home/$LC_USERNAME/my_secrets"
echo $(git-secret cat artifactory.apikey)
