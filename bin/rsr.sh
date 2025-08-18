#!/bin/sh

PROG=$1

sudo -u msa_oper shell-run-env.plx mail page quiet $PROG -u 129 $@
