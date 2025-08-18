#/bin/sh

SETTLEMENT_FILE=$1
TWO_TASK="MSA1_IT"

cat $SETTLEMENT_FILE | perl -MOctaneAuthSettle::OctaneGateway -e 'OctaneAuthSettle::OctaneGateway::direct_handler("text/xml")'
