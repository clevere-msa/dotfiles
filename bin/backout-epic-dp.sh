#/bin/sh

if [ "$#" -ne 1 ]; then
    echo "run date in YYYYMMDD format required as first parameter";
    exit 1
fi

RUNDATE=$1

RUN_ENV='/usr/bin/airbp-run-env.plx'
BIN_DIR=$BIN_DIR

# all steps backout in order with date
# group 3
$RUN_ENV $BIN_DIR/airbp_daily_report_distributor_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_dtr_fax_backout.plx -u 883 -s -d $RUNDATE

# group 2
$RUN_ENV $BIN_DIR/airbp_daily_eft_file_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_create_bpretail_file_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_move_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_avcard_extract_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_dtr_create_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_summary_report_create_backout.plx -u 883 -s -d $RUNDATE

# group 1
$RUN_ENV $BIN_DIR/airbp_daily_calc_merchant_payout_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_merchant_payment_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_fet_adjustment_xml_load_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_currency_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_fee_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_verify_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_settlegate_process_backout.plx -u 883 -s -d $RUNDATE
$RUN_ENV $BIN_DIR/airbp_daily_batch_backout.plx -u 883 -s -d $RUNDATE 
 

