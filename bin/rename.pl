#!/usr/bin/perl 
#
#  This script was developed by Robin Barker (Robin.Barker@npl.co.uk),
#  from Larry Wall's original script eg/move from the perl source.
#
#  This script is free software; you can redistribute it and/or modify it
#  under the same terms as Perl itself.
#
# Larry(?)'s RCS header:
#  RCSfile: move,v   Revision: 4.1   Date: 92/08/07 17:20:30
#
# $RCSfile: move,v $$Revision: 1.5 $$Date: 1998/12/18 16:16:31 $
#
# $Log: move,v $
# Revision 1.5  1998/12/18 16:16:31  rmb1
# moved to perl/source
# changed man documentation to POD
#
# Revision 1.4  1997/02/27  17:19:26  rmb1
# corrected usage string
#
# Revision 1.3  1997/02/27  16:39:07  rmb1
# added -v
#
# Revision 1.2  1997/02/27  16:15:40  rmb1
# *** empty log message ***
#
# Revision 1.1  1997/02/27  15:48:51  rmb1
# Initial revision
#

use strict;
use warnings;

use File::Path;
use File::Basename qw/dirname/;
use Getopt::Long;
Getopt::Long::Configure('bundling');

my $quiet     = q{};
my $multiples = q{};
my $force     = q{};
my $test      = q{};
my $copy      = q{};
my $move      = q{};
my $svn       = q{};
my @ops       = ();

my %actions = ( copy => \$copy, move => \$move, svn => \$svn, );

my $got_options = GetOptions(
    'q|quiet'               => \$quiet,
    't|test'                => \$test,
    'f|force'               => \$force,
    'r|rename'              => \$move,
    's|svn'                 => \$svn,
    'c|copy'                => \$copy,
    'o|op=s'                => \@ops,
    'm|multiple-versions=s' => \$multiples,
);

die "Usage: rename [-qvnf] [-r | -c] [-o regex ...] [filenames]\n"
    if !$got_options || @ops == 0;
die "Must use either -c, -r or -s option\n"
    if scalar( grep { $$_ } values %actions ) != 1;

$quiet = 0 if $test;

my $action = $copy ? '/bin/cp'   : $move ? '/bin/mv' : '/usr/bin/svn mv';
my $verb   = $copy ? 'copy' : 'move';

if ( !@ARGV ) {
    print "reading filenames from STDIN\n" if !$quiet;
    @ARGV = <STDIN>;
    chop(@ARGV);
}

my %file_versions = ();

foreach my $old (@ARGV) {
    my $new;

    {
        local $_ = $old;
        foreach my $op (@ops) {
            if ( 0 && $op =~ m/\$\d/ ) {
                my $m = reverse $op;
                if ( $m =~ m{^/} ) {
                    $m =~ s{^/[^/]+}{};
                }
                else {
                    $m =~ s/^}[^\{]+{//;
                }
                $m = reverse $m;
                $m =~ s/^s/m/;
                print "$_ =~ $m: ";
                eval $m;
                print "$1 $2 $3 $4 $5 $6\n";
            }
            eval $op;
            die $@ if $@;
        }
        $new = $_;
    }

    if ($multiples) {
        ++$file_versions{$new};
        my $this_version = $file_versions{$new};
        $new =~ s/$multiples/$this_version/ge;
    }

    my $msg;

    if ( $old eq $new ) {
        $msg = "$old => $new: ignored";
    }
    elsif ( -e $new and !$force ) {
        $msg = "$old => $new: failed, $new already exists";
    }
    else {
        $msg = "$old => $new: ";
        my $did = $copy ? 'copied' : 'moved';
        if ($test) {
            $msg .= $did;
        }
        else {
            my $dir = -f $old ? dirname($new) : $new;
            if ( !-d $dir ) {
                eval { mkpath $dir };
                if ($@) {
                    $msg .= "failed to create destination $dir, $@";
                }
                else {
                    $msg .= "created destination $dir, ";
                }
            }
            if ( -d $dir ) {
                if ( $action eq 'cp' and -d $old ) {
                    $action .= ' -R';
                    $old    .= '/*';
                }
                my $output = `$action $old, $new`;
                if ( $? == -1 ) {
                    $msg = "failed $verb, $!";
                }
                else {
                    $msg = $did;
                }
            }
            $msg = "$old => $new: $msg";
        }
    }
    $msg .= "\n";
    if ( !$quiet ) {
        print $msg;
    }
    elsif ( $msg =~ m/\: failed / ) {
        warn $msg;
    }
}

__END__

=head1 NAME

move - moves multiple files

=head1 SYNOPSIS

  B<move> S<[ B<-v> ]> S<[ B<-n> ]> S<[ B<-f> ]> I<perlexpr> S<[ I<files> ]>

=head1 DESCRIPTION

C<move>
moves the filenames supplied according to the rule specified as the
first argument.
The I<perlexpr> 
argument is a Perl expression which is expected to modify the C<$_>
string in Perl for at least some of the filenames specified.
If a given filename is not modified by the expression, it will not be
moved.
If no filenames are given on the command line, filenames will be read
via standard input.

For example, to move all files matching C<*.bak> to strip the extension,
you might say

  move 's/\.bak$//' *.bak

To translate uppercase names to lower, you'd use

  move 'y/A-Z/a-z/' *

=head1 OPTIONS

=over 8

=item B<-v>, B<--quiet>

Quiet: don't print names of files successfully moved.

=item B<-n>, B<--no-act>

No Action: show what files would have been moved.

=item B<-f>, B<--force>

Force: overwrite existing files.

=back

=head1 ENVIRONMENT

No environment variables are used.

=head1 AUTHOR

Larry Wall

=head1 SEE ALSO

mv(1), perl(1)

=head1 DIAGNOSTICS

If you give an invalid Perl expression you'll get a syntax error.

=head1 BUGS

The original C<move> did not check for the existence of target filenames,
so had to be used with care.  I hope I've fixed that (Robin Barker).

=cut

