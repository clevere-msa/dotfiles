#!/bin/bash 

PROJECT=$1
VERSION=$2
BUILD=$3
COMMIT=$4
GROUP=$5

if [[ -z $GROUP ]]
then
    GROUP=MSA_TOOLS
fi

if [[ -z $COMMIT ]]
then
    COMMIT=HEAD
fi

echo git archive \
echo     --remote ssh://git@gitlab.us.bank-dns.com:2222/$GROUP/$PROJECT.git \
echo     --format tar.gz \
echo     --output ../../SOURCES/$PROJECT-$VERSION.$BUILD.tar.gz \
echo     \"$COMMIT\"
git archive \
    --remote ssh://git@gitlab.us.bank-dns.com:2222/$GROUP/$PROJECT.git \
    --format tar.gz \
    --output ../../SOURCES/$PROJECT-$VERSION.$BUILD.tar.gz \
    "$COMMIT"
