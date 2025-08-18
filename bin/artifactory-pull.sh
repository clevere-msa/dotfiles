#!/usr/bin/bash

trap "exit 1" TERM
export TOP_PID=$$

function fatal_error() {
    local progname=$(basename $0)
    printf "%s\n" "$progname: $*" >>/proc/self/fd/2
    kill -s TERM $TOP_PID
}

function get_artifactory_project_url() {
    local repo_nickname=$1

    if [ "$repo_nickname" = "airbp" ]; then
       echo "msa_airbp-generic-virtual"
    elif [ "$repo_nickname" = "apps" ]; then
       echo "msa_apps-generic-virtual"
    elif [ "$repo_nickname" = "authsys" ]; then
       echo "msa_-authsys-generic-virtual"
    elif [ "$repo_nickname" = "branded" ]; then
       echo "msa_branded-generic-virtual"
    elif [ "$repo_nickname" = "epic" ]; then
       echo "msa_airbp-generic-virtual"
    elif [ "$repo_nickname" = "framework" ]; then
       echo "msa_framework-generic-virtual"
    elif [ "$repo_nickname" = "msalib" ]; then
       echo "msa_libnix-generic-virtual"
    elif [ "$repo_nickname" = "opsver" ]; then
       echo "msa_opsver-generic-virtual"
    elif [ "$repo_nickname" = "pos" ]; then
       echo "msa_-pos-generic-virtual"
    elif [ "$repo_nickname" = "pos-svcs" ]; then
       echo "msa_pos_services-generic-virtual"
    elif [ "$repo_nickname" = "pos-services" ]; then
       echo "msa_pos_services-generic-virtual"
    elif [ "$repo_nickname" = "pos_services" ]; then
       echo "msa_pos_services-generic-virtual"
    elif [ "$repo_nickname" = "settlsys" ]; then
       echo "msa_settlsys-generic-virtual"
    elif [ "$repo_nickname" = "shell" ]; then
       echo "msa_shell-generic-virtual"
    elif [ "$repo_nickname" = "titan" ]; then
       echo "msa_shell-generic-virtual"
    elif [ "$repo_nickname" = "tools" ]; then
       echo "msa_tools-generic-virtual"
    else
        fatal_error "Unknown repo $repo_nickname"
    fi
}

ZIP_FN=$1
REPO=`get_artifactory_project_url "$2"`

LC_USERNAME=$(echo ${LOGNAME} | tr "[:upper:]" "[:lower:]")
API_KEY=$(/home/$LC_USERNAME/bin/artifactory_api_key.sh)
ARTIFACTORY_URL="https://artifactory.us.bank-dns.com/artifactory"
DOWNLOAD_URL="$ARTIFACTORY_URL/$REPO/$ZIP_FN"
CERT_FN=/etc/pki/tls/certs/usb_chain.pem

/usr/bin/curl --cacert $CERT_FN -H "X-JFrog-Art-Api:$API_KEY" -O $DOWNLOAD_URL
