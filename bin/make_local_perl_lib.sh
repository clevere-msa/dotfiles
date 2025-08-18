#!/bin/bash

HOME="$1"

perl Makefile.PL \
    PREFIX="$HOME" \
    INSTALLPRIVLIB="$HOME/perl-lib" \
    INSTALLSCRIPT="$HOME/bin" \
    INSTALLSITELIB="$HOME/perl-lib" \
    INSTALLBIN="$HOME/bin" \
    INSTALLMAN1DIR="$HOME/lib/perl5/man" \
    INSTALLMAN3DIR="$HOME/lib/perl5/man3"
