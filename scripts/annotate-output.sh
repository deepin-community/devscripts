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

# TODO: Switch from using `/usr/bin/printf` to the (likely built-in) `printf`
#       once POSIX has standardised `%q` for that
#       (see https://austingroupbugs.net/view.php?id=1771) and `dash`
#       implemented it.

define_get_prefix() {
	eval " get_prefix() {
		/usr/bin/printf '%q' $(/usr/bin/printf '%q' "$1")
	}"
}

define_handler_with_date_conversion_specifiers() {
	eval " handler() {
		while IFS= read -r line; do
			printf '%s%s: %s\\n' \"\$(date $(/usr/bin/printf '%q' "$1") )\" \"\$1\" \"\$line\"
		done
		if [ -n \"\$line\" ]; then
			printf '%s%s: %s' \"\$(date $(/usr/bin/printf '%q' "$1") )\" \"\$1\" \"\$line\"
		fi
	}"
	define_get_prefix "${1#+}"
}

define_handler_with_plain_prefix() {
	eval " handler() {
		while IFS= read -r line; do
			printf '%s%s: %s\\n' $(/usr/bin/printf '%q' "$1") \"\$1\" \"\$line\"
		done
		if [ -n \"\$line\" ]; then
			printf '%s%s: %s' $(/usr/bin/printf '%q' "$1") \"\$1\" \"\$line\"
		fi
	}"
	define_get_prefix "$1"
}

usage() {
	printf \
'Usage: %s [OPTIONS ...] [--] PROGRAM [ARGS ...]
Executes PROGRAM with ARGS as arguments and prepends printed lines with a format
string, a stream indicator and `: `.

Options:
 +FORMAT
  A format string that may use the conversion specifiers from the `date`(1)-
  utility.
  The printed string is separated from the following stream indicator by a
  single space.
  Defaults to `%%H:%%M:%%S`.
--raw-date-format FORMAT
  A format string that may use the conversion specifiers from the `date`(1)-
  utility.
  The printed string is not separated from the following stream indicator.
 -h
--help
  Display this help message.
' "${0##*/}"
}

define_handler_with_date_conversion_specifiers '+%H:%M:%S '
while [ -n "${1-}" ]; do
	case "$1" in
	+*%*)
		define_handler_with_date_conversion_specifiers "$1 "
		shift
		;;
	+*)
		define_handler_with_plain_prefix "${1#+} "
		shift
		;;
	--raw-date-format)
		if [ "$#" -lt 2 ]; then
			printf '%s: The `--raw-date-format`-option requires an argument.\n' "${0##*/}" >&2
			exit 125
		fi
		case "$2" in
			*%*) define_handler_with_date_conversion_specifiers "+$2";;
			*) define_handler_with_plain_prefix "${2#+}";;
		esac
		shift 2
		;;
	-h|--help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	*)
		break
		;;
	esac
done

if [ "$#" -lt 1 ]; then
	printf '%s: No program to be executed was specified.\n' "${0##*/}" >&2
	exit 127
fi

printf 'I: annotate-output %s\n' '###VERSION###'
printf 'I: prefix='
get_prefix
printf '\n'
{ printf 'Started'; /usr/bin/printf ' %q' "$@"; printf '\n'; } | handler I

# The following block redirects FD 2 (STDERR) to FD 1 (STDOUT) which is then
# processed by the STDERR handler. It redirects FD 1 (STDOUT) to FD 4 such
# that it can later be moved to FD 1 (STDOUT) and handled by the STDOUT handler.
# The exit status of the program gets written to FD 2 (STDERR) which is then
# captured to produce the correct exit status as the last step of the pipe.
# Both the STDOUT and STDERR handler output to FD 3 such that after exiting
# with the correct exit code, FD 3 can be redirected to FD 1 (STDOUT).
{
  {
    {
      {
        {
          "$@" 2>&1 1>&4 3>&- 4>&-; printf "$?\n" >&2;
        } | handler E >&3;
      } 4>&1 | handler O >&3;
    } 2>&1;
  } | { IFS= read -r xs; exit "$xs"; };
} 3>&1 && {         printf 'Finished with exitcode 0\n'    | handler I; exit 0;    } \
       || { err="$?"; printf "Finished with exitcode $err\n" | handler I; exit "$err"; }
