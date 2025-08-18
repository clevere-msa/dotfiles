#!/usr/bin/perl -s
##
## makerandom - interface to crypt::random
##
## Copyright (c) 1998, Vipul Ved Prakash.  All rights reserved.
## This code is free software; you can redistribute it and/or modify
## it under the same terms as Perl itself.
##
 
use Crypt::Random qw( makerandom makerandom_itv );
use Math::BigInt;
use MIME::Base64;

my @enc = ("A".."Z", "a".."z", "0".."9", "+", "/"); # Array of mapping from pieces to encodings

$strength ||= 0;
$uniform  ||= 0;
$num      ||= 1;
$encode   ||= 'int';
$upper    ||= 0;
$lower    ||= 0;
 
unless ( $size || $lower )  { 
    my $name = $0; 
    $name =~ s{.*/}{}msx;
    print "usage: $name [options] \
       -size=bitsize \
       -strength=[01] \
       -dev=device \
       -lower=lower_bound \
       -upper=upper_bound \
       -uniform=uniform \
       -encode=(hex|oct|b64|int) \
       -num=quantity\n";
    exit 0;
}

for my $i ( 1 .. $num ) {
    my $s
        = ($lower)
        ? makerandom_itv( Lower => $lower, Upper => $upper, Strength => $strength, Device => $dev )
        : makerandom( Size => $size, Strength => $strength, Device => $dev, uniform => $uniform );
    my $n = Math::BigInt->new($s);
    if ( $encode eq 'hex' ) {
        print $n->as_hex();
    }
    elsif ( $encode eq 'oct' ) {
        print $n->as_oct();
    }
    elsif ( $encode eq 'b64' ) {
        print to_base64($n);
    }
    else {
        print $n->bstr();
    }
    print "\n"; 
}

exit 0;

sub to_base64 {
    my $n = shift;

    my @sixes  =  unpack '(A6)*', $n->to_bin();  # group bits 6 at a time
    my $pad    =  6 - length $sixes[$#sixes];    # 0 pad for 6-bit alignment
    $sixes[-1] .= '0' x $pad;
    my @s      =  map { bits2chars($_) } @sixes; # 6-bit strings to chars
    $s[$#s]    .= '=' x ( $pad % 3 );            # append padding indicator
    return join q{}, @s;
}

sub bits2chars { 
	my $bits = shift;
   
    my $ord = unpack 'c', pack( 'b6', join q{}, reverse split q{}, $bits );
    return $enc[$ord];
}
