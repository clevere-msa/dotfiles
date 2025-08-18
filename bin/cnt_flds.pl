#!/usr/bin/perl

use strict;

my $fn  = shift;
my $sep = shift || qq{,};
my $len = shift || 2;

open FH, '<', $fqn;
sysread( FH, my $data, -s $fqn );
close FH;

foreach my $line ( split /\r?\n/, $data ) {
    $fields_per_line{ substr $line, 0, $len }{ scalar split /$sep/, $line }++;
}

my %fields_per_line = ();

print
    map { sprintf "lines w/ record_type %s and %s fields: %s\n", @{$_} }
    map { $_->[1] }
    sort{ $a->[0] cmp $b->[0] }
    map { [ ( sprintf '%s%05d', @{$_}[ 0, 1 ] ), $_ ] }
    map { my @i = @{$_}; map { [ $i[0], $_, $i[1]->{$_} ] } keys %{ $i[1] } }
    map { [ $_, $fields_per_line{$_} ] }
    keys %fields_per_line;

exit;
