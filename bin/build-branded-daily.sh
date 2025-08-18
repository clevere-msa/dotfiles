#!/usr/bin/bash

TIMESTAMP=$(date +'%Y%m%d_%H%M%S');
BUILD_NAME="branded.$TIMESTAMP.set.zip";
BRANCH="daily"
CUR_DIR=$PWD;

echo "Building >$BUILD_NAME<";
/project/util/bin/gitbuild.pl -p branded -b $BRANCH  -n $TIMESTAMP;
