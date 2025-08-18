#/usr/bin/perl

use strict;
use warnings;
use English;

use Carp qw/croak/;
use Readonly;

Readonly::Scalar my $BLOCK_SIZE => 2**16;
Readonly::Scalar my $FOR_REALLY => 'pull_the_trigger';

my ( $regex, $input_file, $output_file, $for_real ) = @ARGV;

if ( !defined $for_real ) {
    $for_real = q{};
}
elsif ( $for_real eq $FOR_REALLY ) {
    $for_real = 1;
}
else {
    croak "all my users type '$FOR_REALLY' at the end, or type nothing.";
}

my $substitution = eval $regex;

open my $in, '<', $input_file;
if ($for_real) {
    open my $out, '>', $output_file;
}

while ( read( $in, my $block, $BLOCK_SIZE ) ) {
    $block =~ $substitution;
    if ($for_real) {
        print {$out} $block;
    }
    else {
        print $block;
        last;
    }
}

close $in;

if ($for_real) {
    close $out;
}

exit 0;
