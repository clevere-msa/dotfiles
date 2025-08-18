#!/usr/bin/perl
#
# 	Program Description
# 	-------------------
####################################################################################################################################
use strict;
use Carp;
use Compress::Zlib;
use MSA::Shared::DBConnectionManager;
use Getopt::Long;

my $process_run_id  = undef;
my @report_type_ids = ();
my $output_dir      = q{./};
my $server          = 'msa_dev';
my $help            = q{};

GetOptions(
    'process-run-id|p=i'   => \$process_run_id,
    'report-type-id|r=i'   => \@report_type_ids,
    'output-directory|o=s' => \$output_dir,
    'db-server|s=s'        => \$server,
    'help|h'               => \$help,
);

if ( !defined $process_run_id ) {
    usage('--process-run-id required!');
}
elsif ( !scalar @report_type_ids ) {
    usage('--report-type-id required!');
}
elsif ($help) {
    usage();
}

print "connecting to DB on $server\n";

my $dbh
    = MSA::Shared::DBConnectionManager->get_connection( $server, 'shell_user',
    { AutoCommit => 0, PrintError => 1, RaiseError => 1 } )
    or croak "DB connection to $server failed";
$dbh->{'LongReadLen'} = 10_000_000;

my $file_name = q{};
my $file_data = q{};
eval {
    my $sth_r = $dbh->prepare(<<'EOSQL');
        SELECT a.report_filename,
               a.report_clob
		FROM   shell.processing_report a
		WHERE  a.process_run_id            = :process_run_id
		AND    a.processing_report_type_id = :report_type_id
EOSQL
    foreach my $rt_id (@report_type_ids) {
        $sth_r->bind_param( ':process_run_id', $process_run_id );
        $sth_r->bind_param( ':report_type_id', $rt_id );
        $sth_r->execute();
        while ( ( $file_name, $file_data ) = $sth_r->fetchrow_array() ) {
            print "uncompressing file_data for $file_name\n";
            $file_data = uncompress($file_data);
            print "writing report: $file_name\n";
            open my $fh, q{>}, "$output_dir/$file_name";
            print {$fh} $file_data;
            close $fh;
        }
        $sth_r->finish();
    }
    1;
} or do {
    croak "DB execute error obtaining Data File: $@";
};

print "done\n";
exit 0;

sub usage {
    my $msg = shift;

    if ( defined $msg ) {
        print $msg, "\n";
    }

    ( my $me = $0 ) =~ s{^.*/}{}msx;

    print <<"EOUSAGE";
$me - pull Shell daily processing output reports

    $me [OPTIONS]

OPTIONS
    --process-run-id    -p  PROCESS_RUN_ID  process_run_id for the output file you need
    --report-type-id    -r  REPORT_TYPE_ID  look at output of SELECT * FROM shell.r_processing_report_type_ri
    --output-directory  -o  PATH            Where to put the files, default is current working directory
    --db-server         -s  DB SERVER NAME  DB server, eq. msa_dev, msa1_it, etc.
    --help              -h                  This is it. Did you expect more?

EOUSAGE

    exit( $msg ? 1 : 0 );
}
