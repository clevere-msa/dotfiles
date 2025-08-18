#!/usr/bin/perl

use strict;

use XML::LibXML;

foreach my $argv_file (@ARGV) {
    my $source_file = &untaint_file($argv_file);

    my $parser = XML::LibXML->new();    # Create an XML parser object.

    eval {
        my $doc = $parser->parse_file($source_file);    # Parse the XML file
        $doc->validate();                               # Validate it
        1;
    }
    or do {    # Any errors after parsing and validating?
        warn "\n$@\n";
        print "$source_file failed XML validation\n";
        next;
    };

    print "$source_file syntax OK\n";
}

sub untaint_file {
    my $file = shift;

    unless ( $file =~ /^([\/\w\.\-\:]+)$/ ) {
        print STDOUT("file $file has invalid character(s)!");
        exit 1;
    }

    return $1;
}
