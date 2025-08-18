#!/usr/bin/perl

use strict;
use Class::ISA;
use List::Util qw/first/;

my $subclass = shift;

( my $path = $subclass ) =~ s{::}{/}g;

my $pm = first { -e $_ } map {"$_/$path.pm"} @INC;
die "couldn't find $subclass in \@INC\n"
    if !defined $pm;

require $pm;
my %seen  = ();
my @class = Class::ISA::self_and_super_path($subclass);

print "for $subclass defined in $pm:\n\n";

foreach my $class (@class) {
    print "  from $class:\n";
    foreach my $method ( class_methods($class) ) {
        next if $seen{$method}++;
        print "    $method\n";
    }
    print "\n";
}

exit;

sub class_methods {
    my ($testclass) = @_;

    no strict 'refs';
    my @methods =
        grep { defined &{ ${"${testclass}::"}{$_} } }
        grep { my $x = $_; $x !~ m/^_/ }
        keys %{"${testclass}::"};

    return sort @methods;
}
