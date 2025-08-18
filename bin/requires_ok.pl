#!/usr/bin/perl

use strict;

my $module = shift;
my $status = eval { require $module; };

print defined $status
    ? "ok require '$module'\n"
    : "not ok require '$module': $@;\n";

exit defined $status ? 0 : 1;
