#!/usr/bin/perl

use 5.012;
use warnings;
use Readonly;
use English qw(-no_match_vars);
use Carp;
use Getopt::Long;

use MSA::Shared::DBConnectionManager;

Readonly my $SQL => <<'EOSQL';
DECLARE
  l_job_id    shell.fw_job.job_id%TYPE;
  r_row_id    ROWID;
  l_prog_name shell.bill_step.program_name%TYPE;
  l_task_id   shell.fw_job.task_id%TYPE;

  dir VARCHAR2(1) := :direction;

  CURSOR tasks IS
    SELECT program_name, task_id
    FROM   shell.bill_step
    WHERE  is_backout = decode(dir, 'F', 'N', 'Y')
    ORDER  BY decode(dir, 'F', step, 0 - step);
BEGIN
  FOR t IN tasks
  LOOP
    r_row_id := shell.shell_job_p.submit_emboss_extract(t.task_id, 8472, l_job_id,  0);
  END LOOP;
END;
EOSQL

my $backout = q{};
my $env     = exists $ENV{TWO_TASK} ? $ENV{TWO_TASK} : q{msa_dev};
my $help    = q{};

GetOptions(
    'backout'     => \($backout),
    'environment' => \($env),
    'help'        => \($help)
);

exit usage(0) if $help;

my $direction = $backout ? 'B' : 'F';

die
    "$PROGRAM_NAME - environment must be one of msa_dev, msa1_it or msa1_uat if set\n"
    if $env and not $env =~ m/^msa(?:_dev|1_(?:i|ua)t)$/msx;

my $dbh;

eval {
    $dbh = MSA::Shared::DBConnectionManager->get_connection(
        "dbi:Oracle:$env",
        'shell_user',
        {   PrintError   => 0,
            RaiseError   => 0,
            AutoCommit   => 0,
            RowCacheSize => 50,
            LongReadLen  => 2000,
        },
    );
    my $sth = $dbh->prepare("$SQL");
    $sth->bind_param( ':direction', $direction );
    $sth->execute();
    $dbh->commit();
    $dbh->disconnect();
    1;
} or do {
    $dbh->rollback();
    croak "$PROGRAM_NAME - unable to queue billing jobs: $EVAL_ERROR";
};

exit 0;

sub usage {
    my ($exit_status) = @_;

    $exit_status //= 0;

    ( my $progname = $PROGRAM_NAME ) =~ s{^.*/}{}msx;

    say <<"EOHELP";
$progname: run shell billing from linux command line

usage:
    \$ $progname [OPTIONS]

OPTIONS
    backout:     backout billing steps
    environment: chose environment to run under (msa_dev, msa1_dev or msa1_uat)
    help:        this is it
EOHELP

    return $exit_status;
}

END {
    if ( defined $dbh ) {
        $dbh->disconnect();
    }
}
