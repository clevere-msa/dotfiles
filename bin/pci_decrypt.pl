#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 'V1.0.CLE.0.1';

use IO::File;
use IO::Pipe;
use IO::Dir;
use MSA::IO;

use Carp;
use Getopt::Std;

our ( $opt_o, $opt_h, $opt_d, $opt_f, $opt_v, $opt_p );

HELP_MESSAGE() if !getopts('d:f:ovh');
HELP_MESSAGE() if defined $opt_h;
HELP_MESSAGE('No files specified to encrypt')
    if !defined $opt_f && !defined $opt_d;

my $less_pipe = undef;

if ( defined $opt_p ) {
    $opt_v     = undef;
    $less_pipe = IO::Pipe->new();
    $less_pipe->writer( exists $ENV{PAGER} ? $ENV{PAGER} : '/usr/bin/less' )
        or croak "can't open pipe to less for writing: $!\n";
}

foreach my $f ( find_files() ) {
    decrypt_file($f);
}

spew('All done!');

exit 0;

sub spew {
    my (@message) = @_;

    return if !$opt_v;

    print @message, "\n";
}

sub find_files {

    my @files = ();

    return $opt_f if defined $opt_f and -f $opt_f;

    croak "$opt_d is not a valid directory!"
        if !-d $opt_d;

    tie my %dir, 'IO::Dir', $opt_d
        or croak "Could not open directory $opt_d\n";

    spew("Scanning directory $opt_d");

    @files = grep {m/^[^\.]/} grep { -f $_ } sort keys %dir;

    spew( map {"Added $_ to decypt queue\n"} @files );

    return @files;
}

sub decrypt_file {
    my $encrypted_fn = shift;

    my $fh = MSA::IO->new( '<', $encrypted_fn, 'Reading settlement file' )
        or return carp "Couldn't open file $encrypted_fn for reading: $!";
    *FH = *$fh;
    my $plaintext = join q{}, <FH>;
    $fh->close();

    my $decrypted_fn = $encrypted_fn . defined $opt_o ? q{} : '.out';

    $fh = defined $opt_p ? $less_pipe : IO::File->new( $decrypted_fn, 'w' );

    $fh->print($plaintext);

    spew( "Decrypted $encrypted_fn ",
        $opt_o ? 'in place' : "to $decrypted_fn" );

    return;
}

sub HELP_MESSAGE {
    my (@message) = @_;

    if ( scalar @message ) {
        print @message, "\n";
    }

    print <<'EOUSAGE';
Usage: pci_decrypt.pl <options>
    -f <filename>   Processes single file specified
    -d <directory>  Processes ALL files in directory specified
    -l              pipe plaintext to 'less'
    -o              Overwrites original file with plaintext
    -v              Verbose logging

    <filename>.out  will be the decrypted file if -o is not specified
EOUSAGE

    exit( scalar @message > 0 ? 1 : 0 );
}
