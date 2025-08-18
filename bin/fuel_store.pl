#!/usr/bin/perl
#
#   fuel_legacy_loader_store.plx - Program to stage edited Settlement batches from OpsVer for reprocessing.
#
#
#   12/02/10   V1.0.MDC.0.0   Matthew Carlson	Written
#
# This program reads a configuration containing the following information
# ( Databse info )
# ( Logging info )
# [ File Source and Archive Info
# (Source dir , Archive dir ),
# (Source dir , Archive dir ),
# (Source dir , Archive dir ),
# ]
#
# When given a file fromt he command line, it will identify which condiguration directory is the source, and place this file into the database
# When run from autosys, it will loop through all configuration directories, and place all files into the database
# After placing a file in the datbase, it will move it to the Archive Dir

# mkdir /project/settlesystem/log/fuel_legacy_loader_store
# CREATE /project/settlesystem/config/fuel_legacy_loader_store.config.xml
# create /project/settlesystem/dtd/FuelStore.v1.dtd

use strict;
use warnings;
use Readonly;
use Carp;
use English qw/-no_match_vars/;

use IO::File;
use File::Basename;
use Getopt::Std;
use MSA::CommonFunctions qw( timestamp datestamp );

use Env;
use Sys::Hostname;
use SettleSys::DBStore;

Readonly our $VERSION => 'V1.0.CLE.1.0';

our ( $opt_d, $opt_h );

#       basic information
#
Readonly my $PROGRAM        => ( fileparse($PROGRAM_NAME) )[0];
Readonly my $PROG_NAME      => basename( $PROGRAM, '.pl' );
Readonly my $TRUE           => 1;
Readonly my $FALSE          => q{};
Readonly my $LOG_FILE_FLAGS => ( O_CREAT | O_WRONLY | O_APPEND );
Readonly my $LOG_FILE_MODE  => oct(664);
Readonly my $FILE_MASK      => oct(2);
Readonly my $HOST           => hostname();
Readonly my $ROOT_DN        => (
    exists $ENV{SETL_HOME}
    ? $ENV{SETL_HOME}
    : '/project/settlesystem'
);

my $debug_flag = $FALSE;
my $log_fh     = *STDERR;

local $OUTPUT_AUTOFLUSH = 1;

sub usage {

    print <<"EOHELP";
Usage: $PROGRAM_NAME [OPTIONS]

OPTIONS
    -d  Debug mode Active
    -h  Show this help

EOHELP

    return 0;
}

sub main {
    exit usage() if defined $opt_h;

    $debug_flag = defined $opt_d ? $TRUE : $FALSE;

    initialize_log();

    write_log( $TRUE,  "Running from $HOST" );
    write_log( $FALSE, "AutoSys run" );

    my $ok = eval {
        SettleSys::DBStore->load_settlement_files_from_filesystem($log_fh);
        1;
    };
    if ( not $ok ) {
        $EVAL_ERROR ||= 'Unknown error';
        croak "Error loading files: $EVAL_ERROR";
    }

    write_log( $FALSE, "Normal program completion" );

    return;
}

#
#   Initialize_Log
#
#   -- Open logfile @ <root>/<Log directory from the config file>/<Program Name>/log.<Date in YYYYMMDD Format>
#
#   -- Set $Log_File_Handle from STDERR to the Logfile
#
sub initialize_log {
    my $log_dn = "$ROOT_DN/log/$PROG_NAME";

    croak "Log Directory $log_dn does not exist"
        if not -d $log_dn;

    my $log_fn = sprintf '%s/log.%s', $log_dn, datestamp('YYYYMMDD');

    umask $FILE_MASK;

    sysopen $log_fh, $log_fn, $LOG_FILE_FLAGS, $LOG_FILE_MODE
        or croak "$PROGRAM: error opening log file '$log_fn': $OS_ERROR";

    write_log( $FALSE, ">>>>> Begin Log <<<<<" );
    write_log( $FALSE, "called by $PROGRAM" );
    write_log( $TRUE,  "Leaving Initialize_Log." );

    return;
}

#
#   WriteLog
#
#   -- Log <$Text> to $log_fh
#
sub write_log {
    my ( $check_debug, $text ) = @_;

    return if $check_debug and not $debug_flag;

    my $log_message = sprintf "%s[%05d]%s: %s\n",
        timestamp(), $PID, $PROG_NAME, $text;

    print $log_fh $log_message;
    print $log_message;

    return;
}

main();

