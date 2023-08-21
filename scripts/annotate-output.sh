#!/bin/sh

# Copyright 2019-2023 Johannes Schauer Marin Rodrigues <josch@debian.org>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

set -eu

PROGNAME=${0##*/}

handler() {
	while IFS= read -r line; do
		printf "%s %s: %s\n" "$($1)" "$2" "$line"
	done
	if [ -n "$line" ]; then
		printf "%s %s: %s" "$($1)" "$2" "$line"
	fi
}

usage() {
	echo \
"Usage: $PROGNAME [options] program [args ...]
  Run program and annotate STDOUT/STDERR with a timestamp.

  Options:
   +FORMAT    - Controls the timestamp format as per date(1)
   -h, --help - Show this message"
}

FMT="+%H:%M:%S"
while [ -n "${1-}" ]; do
	case "$1" in
	+*)
		FMT="$1"
		shift
		;;
	-h|-help|--help)
		usage
		exit 0
		;;
	*)
		break
		;;
	esac
done

if [ $# -lt 1 ]; then
	usage
	exit 1
fi

# shellcheck disable=SC2317
plainfmt() { printf "%s" "$FMT"; }
# shellcheck disable=SC2317
datefmt() { date "$FMT"; }
case "$FMT" in
	*%*) formatter=datefmt;;
	*) formatter=plainfmt; FMT="${FMT#+}";;
esac

echo Started "$@" | handler $formatter I

# The following block redirects FD 2 (stderr) to FD 1 (stdout) which is then
# processed by the stderr handler. It redirects FD 1 (stdout) to FD 4 such
# that it can later be move to FD 1 (stdout) and handled by the stdout handler.
# The exit status of the program gets written to FD 2 (stderr) which is then
# captured to produce the correct exit status as the last step of the pipe.
# Both the stdout and stderr handler output to FD 3 such that after exiting
# with the correct exit code, FD 3 can be redirected to FD 1 (stdout).
err=0
{
  {
    {
      {
        {
          "$@" 2>&1 1>&4 3>&- 4>&-; echo $? >&2;
        } | handler $formatter E >&3;
      } 4>&1 | handler $formatter O >&3;
    } 2>&1;
  } | { read -r xs; exit "$xs"; };
} 3>&1 || err=$?

echo "Finished with exitcode $err" | handler $formatter I
exit $err
