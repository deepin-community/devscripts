#!/bin/bash

# wnpp-alert -- check for installed packages which have been orphaned
#               or put up for adoption

# This script is in the PUBLIC DOMAIN.
# Authors:
# Arthur Korn <arthur@korn.ch>

# Arthur wrote:
# Get a list of packages with bugnumbers. I tried with LDAP, but this
# is _much_ faster.
# And I (Julian) tried it with Perl's LWP, but this is _much_ faster
# (startup time is huge).  And even Perl with wget is slower by 50%....

set -e

PROGNAME=${0##*/}
# TODO: Remove use of OLDCACHEDDIR post-Stretch
OLDCACHEDIR=~/.devscripts_cache
OLDCACHEDDIFF="${OLDCACHEDIR}/wnpp-diff"
CACHEDIR=${XDG_CACHE_HOME:-~/.cache}
CACHEDIR=${CACHEDIR%/}/devscripts
CACHEDDIFF="${CACHEDIR}/wnpp-diff"
CURLORWGET=""
GETCOMMAND=""

usage() { echo \
"Usage: $PROGNAME [--help|-h|--version|-v|--diff|-d] [package ...]
  List all installed (or listed) packages with Request for
  Adoption (RFA), Request for Help (RHF), or Orphaned (O)
  bugs against them, as determined from the WNPP website.
  https://www.debian.org/devel/wnpp"
}

version() { echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This script is in the PUBLIC DOMAIN.
Authors: Arthur Korn <arthur@korn.ch>
Modifications: Julian Gilbey <jdg@debian.org>"
}

wnppdiff() {
    if [ -f "$OLDCACHEDDIFF" ]; then
        mv "$OLDCACHEDDIFF" "$CACHEDDIFF"
    fi
    if [ ! -f "$CACHEDDIFF" ]; then
        # First use
        comm -12 $WNPP_PACKAGES $INSTALLED | sed -e 's/\([+.]\)/\\\1/g' | \
          xargs -I{} grep -E '^[A-Z]+ [0-9]+ {} ' $WNPP | \
          tee "$CACHEDDIFF"
    else
        comm -12 $WNPP_PACKAGES $INSTALLED | sed -e 's/\([+.]\)/\\\1/g' | \
          xargs -I{} grep -E '^[A-Z]+ [0-9]+ {} ' $WNPP > "$WNPP_DIFF" || true
        sort -o "$CACHEDDIFF" "$CACHEDDIFF"
        sort -o "$WNPP_DIFF" "$WNPP_DIFF"
        comm -3 "$CACHEDDIFF" "$WNPP_DIFF" | \
          sed -e 's/\t/\+/g' -e 's/^\([^+]\)/-\1/g'
        mv "$WNPP_DIFF" "$CACHEDDIFF"
    fi
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then usage; exit 0; fi
if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then version; exit 0; fi

if command -v wget > /dev/null; then
    CURLORWGET="wget"
    GETCOMMAND="wget -q -O"
elif command -v curl > /dev/null; then
    CURLORWGET="curl"
    GETCOMMAND="curl -qfsL -o"
else
    echo "$PROGNAME: need either the wget or curl package installed to run this" >&2
    exit 1
fi


# Let's abandon this directory from now on, these files are so small
# (see bug#309802)
if [ -d "$CACHEDIR" ]; then
    rm -f "$CACHEDIR"/orphaned "$CACHEDIR"/rfa_bypackage
fi

WNPPTMPDIR=$(mktemp --directory --tmpdir wnppalert.XXXXXX)
trap 'rm -rf "$WNPPTMPDIR"' EXIT
cd "$WNPPTMPDIR"

INSTALLED=installed
WNPP=wnpp
WNPP_PACKAGES=wnpp_packages

if [ "$1" = "--diff" ] || [ "$1" = "-d" ]; then
    shift
    WNPP_DIFF=wnpp_diff
fi

# Here's a really sly sed script.  Rather than first grepping for
# matching lines and then processing them, this attempts to sed
# every line; those which succeed execute the 'p' command, those
# which don't skip over it to the label 'd'
WNPPTMP=orphaned
$GETCOMMAND $WNPPTMP https://www.debian.org/devel/wnpp/orphaned || \
    { echo "$PROGNAME: $CURLORWGET https://www.debian.org/devel/wnpp/orphaned failed" >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/O \1 \2 -- \3/; T d; p; : d' $WNPPTMP > $WNPP

WNPPTMP=rfa_bypackage
$GETCOMMAND $WNPPTMP https://www.debian.org/devel/wnpp/rfa_bypackage || \
    { echo "$PROGNAME: $CURLORWGET https://www.debian.org/devel/wnpp/rfa_bypackage" >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFA \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

WNPPTMP=help_requested
$GETCOMMAND $WNPPTMP https://www.debian.org/devel/wnpp/help_requested || \
    { echo "$PROGNAME: $CURLORWGET https://www.debian.org/devel/wnpp/help_requested" >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFH \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

cut -f3 -d' ' $WNPP | sort > $WNPP_PACKAGES

# A list of installed files.

if [ $# -gt 0 ]; then
    printf '%s\n' "$@" | sort -u > $INSTALLED
else
    dpkg-query -W -f '${Package} ${Status}\n${Source} ${Status}\n' | \
        awk '/^[^ ].*install ok installed/{print $1}' | \
        sort -u \
        > $INSTALLED
fi

if [ -n "$WNPP_DIFF" ]; then
    # This may fail when run from a cronjob (c.f., #309802), so just ignore it
    # and carry on.
    mkdir -p "$CACHEDIR" >/dev/null 2>&1 || true
    if [ -d "$CACHEDIR" ] || [ -d "$OLDCACHEDIR" ]; then
        wnppdiff
        exit 0
    else
        echo "$PROGNAME: Unable to create diff; displaying full output"
    fi
fi

comm -12 $WNPP_PACKAGES $INSTALLED | sed -e 's/\([+.]\)/\\\1/g' | \
xargs -I{} grep -E '^[A-Z]+ [0-9]+ {} ' $WNPP || true
