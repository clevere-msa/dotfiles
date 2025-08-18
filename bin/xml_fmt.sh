#!/bin/sh

XML_FN="$1"

xmllint --memory --format $XML_FN > pp/$XML_FN
