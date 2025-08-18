#!/usr/bin/perl

use IO::File;
use MSA::IO;
use Getopt::Std;
use strict;

use vars
  qw( $VERSION $opt_o $opt_h $opt_d $opt_f $opt_v );

BEGIN {
  $VERSION = 'V1.0.JJH.0.0';    # From Version block above
}


sub Usage() {

	print STDERR "Usage: pci_encrypt.pl <options>\n" .
		"-f <filename>   Processes single file specified\n" .
		"-d <directory>  Processes ALL files in directory specified\n" .
		"-o              Overwrites original file\n" .
		"-v              Verbose logging\n\n" .
		"<filename>.out  will be the encrypted file if -o is not specified\n";

	exit(1);
}


sub Encrypt_File() {

	my $in_file = shift;
	my $out_file = undef;

	unless ( open(POS_SETTLE_FILE, "<$in_file") ) {
		die "Could not open input file $in_file\n";
	}

	my @file_content = <POS_SETTLE_FILE>;
	close POS_SETTLE_FILE;

	if (defined $opt_o) {
		$out_file = $in_file;
	} else {
		$out_file = $in_file . ".out";
	}

	my $fh = MSA::IO->open('>', $out_file, 'JH util writing enc file');
	$fh->print(@file_content);
	$fh->close();
	print STDOUT "Encrypted $in_file\n" if defined ($opt_v);
}

&Usage() unless getopts('d:f:ovh');
&Usage() if ( defined $opt_h );

my @file_list = ();
my $File = undef;

if (defined $opt_h) {
	&Usage();
}
unless (defined $opt_f ||
    	defined $opt_d) {
	print STDERR "No files specified to encrypt\n";
	&Usage();
}

if (defined $opt_f) {
	push @file_list, $opt_f;
}
if (defined $opt_d) {
	my $Procdir = undef;
	if (not -d $opt_d) {
		die "$opt_d is not a valid directory!";
	}
	unless ( opendir( Procdir, $opt_d ) ) {
		die "Could not open directory $opt_d";
	}
	print STDOUT "Scanning directory $opt_d\n";
	#
	# Check each file listed in the directory
	#
	foreach $File ( sort readdir(Procdir) ) {
		next if -d $File;
		if (substr($File,0,1) ne ".") {
			push @file_list, $File;
			print STDOUT "Adding file $File to list\n";
		}
	}
	closedir(Procdir);
}	

foreach $File (@file_list) {
	&Encrypt_File($File);
}

print STDOUT "All done!\n" if defined ($opt_v);


