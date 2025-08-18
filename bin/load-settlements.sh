#!/bin/bash

SYSTEM="$1"
PROJECT='0'

MSA_OPER=`whoami`
if [ "$MSA_OPER" != "msa_oper" ]
then
    echo "use sudo to run this command as 'msa_oper'"
    exit 1
fi

SETL_HOME='/project/settlesystem'
SETL_CFG="${SETL_HOME}/config/setl_run_env"
SETL_BIN="${SETL_HOME}/bin"

MSA_HOME='/project/msa'
MSA_BIN="${MSA_HOME}/bin"

TDP_PROFILE="${SYSTEM}_settlements"

POS_LOADER_PARAMS='-a -d'
XML_LOADER_PARAMS="-root $SETL_HOME -auto -debug"

BACKDATE="/home/$LOGNAME/bin/backdate-stored-files.pl"

if [ "$SYSTEM" == "shell" ]
then
    echo "Shell not supported by IPP"
    exit 2
    POS_LOADER="shell_loader.plx"
    XML_LOADER="Shell-SettlementLoader.plx"
    PROJECT='9'
elif [ "$SYSTEM" == "airbp" ];
then
    POS_LOADER="airbp_dial_loader.plx"
    POS_LOADER_PARAMS="-a -v -r $SETL_HOME"
    XML_LOADER='AirBP-FuelLegacyLoader.plx'
    PROJECT='3'
elif [ "$SYSTEM" == "branded" ];
then
    POS_LOADER='branded_loader.plx'
    XML_LOADER='MSAviation-FuelLegacyLoader.plx'
    PROJECT='6'
else
    echo "Unknown system '$SYSTEM'"
    exit 2
fi

$SETL_CFG $SETL_BIN/$XML_LOADER $XML_LOADER_PARAMS

$MSA_BIN/fuel_ipp_reprice.pl --project $PROJECT
$MSA_BIN/fuel_verify.pl --project $PROJECT

exit 0;
