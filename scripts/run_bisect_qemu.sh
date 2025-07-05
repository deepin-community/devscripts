#!/bin/sh
#
# Copyright 2020 Johannes Schauer Marin Rodrigues <josch@debian.org>
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

# this script is part of debbisect and usually called by debbisect itself
#
# it accepts eight or ten arguments:
#    1. dependencies
#    2. script name or shell snippet
#    3. mirror URL
#    4. architecture
#    5. suite
#    6. components
#    7. memsize
#    8. disksize
#    9. (optional) second mirror URL
#   10. (optional) package to upgrade
#
# It will create an ephemeral qemu virtual machine using mmdebstrap and
# guestfish using (3.) as mirror, (4.) as architecture, (5.) as suite and
# (6.) as components, install the dependencies given in (1.) and execute the
# script given in (2.).
# Its output is the exit code of the script as well as a file ./pkglist
# containing the output of "dpkg-query -W" inside the chroot.
#
# If not only six but eight arguments are given, then the second mirror URL
# (9.) will be added to the apt sources and the single package (10.) will be
# upgraded to its version from (9.).
#
# shellcheck disable=SC2016

set -exu

if [ $# -ne 8 ] && [ $# -ne 10 ]; then
	echo "usage: $0 depends script mirror1 architecture suite components memsize disksize [mirror2 toupgrade]"
	exit 1
fi

depends=$1
script=$2
mirror1=$3
architecture=$4
suite=$5
components=$6
memsize=$7
disksize=$8

if [ $# -eq 10 ]; then
	mirror2=$9
	toupgrade=${10}
fi

TMPDIR=$(mktemp --tmpdir --directory debbisect_qemu.XXXXXXXXXX)
cleantmp() {
	for f in customize.sh id_rsa id_rsa.pub qemu.log config; do
		rm -f "$TMPDIR/$f"
	done
	rmdir "$TMPDIR"
}

trap cleantmp EXIT
# the temporary directory must be world readable (for example in unshare mode)
chmod a+xr "$TMPDIR"

ssh-keygen -q -t rsa -f "$TMPDIR/id_rsa" -N ""

# The following hacks are needed to go back as far as 2006-08-10:
#
#  - Acquire::Check-Valid-Until "false" allows Release files with an expired
#    Valid-Until dates
#  - Apt::Key::gpgvcommand allows expired GPG keys
#  - Apt::Hashes::SHA1::Weak "yes" allows GPG keys with weak SHA1 signature
#  - /usr/share/keyrings lets apt use debian-archive-removed-keys.gpg
#  - /usr/share/mmdebstrap/hooks/jessie-or-older performs some setup that is
#    only required for Debian Jessie or older
#
debvm-create --skip=usrmerge --size="$disksize" \
	--sshkey="$TMPDIR/id_rsa.pub" --release="$suite" \
	--output="debian-rootfs.img" -- \
	--architecture="$architecture" \
	--components="$components" \
	--aptopt='Acquire::Check-Valid-Until "false"' \
	--aptopt='Apt::Key::gpgvcommand "/usr/libexec/mmdebstrap/gpgvnoexpkeysig"' \
	--aptopt='Apt::Hashes::SHA1::Weak "yes"' \
	--keyring=/usr/share/keyrings \
	--hook-dir=/usr/share/mmdebstrap/hooks/maybe-jessie-or-older \
	--hook-dir=/usr/share/mmdebstrap/hooks/maybe-merged-usr \
	--skip=check/signed-by \
	"$mirror1"

timeout --kill-after=60s 60m \
	debvm-run --image="debian-rootfs.img" \
	--sshport=10022 -- \
	-m "$memsize" \
	-serial mon:stdio \
	> "$TMPDIR/qemu.log" </dev/null 2>&1 &

# store the pid
QEMUPID=$!

# use a function here, so that we can properly quote the path to qemu.log
showqemulog() {
	cat --show-nonprinting "$TMPDIR/qemu.log"
}

# show the log and kill qemu in case the script exits first
trap 'showqemulog; cleantmp; kill $QEMUPID' EXIT

# the default ssh command does not store known hosts and even ignores host keys
# it identifies itself with the rsa key generated above
# pseudo terminal allocation is disabled or otherwise, programs executed via
# ssh might wait for input on stdin of the ssh process

cat << END > "$TMPDIR/config"
Host qemu
	Hostname 127.0.0.1
	User root
	Port 10022
	UserKnownHostsFile /dev/null
	StrictHostKeyChecking no
	IdentityFile $TMPDIR/id_rsa
	RequestTTY no
END

debvm-waitssh 10022

# we install dependencies now and not with mmdebstrap --include in case some
# dependencies require a full system present
if [ -n "$depends" ]; then
	ssh -F "$TMPDIR/config" qemu apt-get update
	# shellcheck disable=SC2046,SC2086
	ssh -F "$TMPDIR/config" qemu env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get --yes install --no-install-recommends $(echo $depends | tr ',' ' ')
fi

# in its ten-argument form, a single package has to be upgraded to its
# version from the first bad timestamp
if [ $# -eq 10 ]; then
	# replace content of sources.list with first bad timestamp
	mirror2=$(echo "$mirror2" | sed 's/http:\/\/127.0.0.1:/http:\/\/10.0.2.2:/')
	echo "deb $mirror2 $suite $(echo "$components" | tr ',' ' ')" | ssh -F "$TMPDIR/config" qemu "cat > /etc/apt/sources.list"
	ssh -F "$TMPDIR/config" qemu apt-get update
	# upgrade a single package (and whatever else apt deems necessary)
	before=$(ssh -F "$TMPDIR/config" qemu dpkg-query -W)
	ssh -F "$TMPDIR/config" qemu env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get --yes install --no-install-recommends "$toupgrade"
	after=$(ssh -F "$TMPDIR/config" qemu dpkg-query -W)
	# make sure that something was upgraded
	if [ "$before" = "$after" ]; then
		echo "nothing got upgraded -- this should never happen" >&2
		exit 1
	fi
	ssh -F "$TMPDIR/config" qemu dpkg-query -W > "./debbisect.$DEBIAN_BISECT_TIMESTAMP.$toupgrade.pkglist"
else
	ssh -F "$TMPDIR/config" qemu dpkg-query -W > "./debbisect.$DEBIAN_BISECT_TIMESTAMP.pkglist"
fi

ssh -F "$TMPDIR/config" qemu dpkg-query --list | cat

# explicitly export all necessary variables
# because we use set -u this also makes sure that this script has these
# variables set in the first place
export DEBIAN_BISECT_EPOCH="$DEBIAN_BISECT_EPOCH"
export DEBIAN_BISECT_TIMESTAMP="$DEBIAN_BISECT_TIMESTAMP"
if [ -z ${DEBIAN_BISECT_MIRROR+x} ]; then
	# DEBIAN_BISECT_MIRROR was unset (caching is disabled)
	true
else
	# replace the localhost IP by the IP of the host as seen by qemu
	DEBIAN_BISECT_MIRROR=$(echo "$DEBIAN_BISECT_MIRROR" | sed 's/http:\/\/127.0.0.1:/http:\/\/10.0.2.2:/')
	export DEBIAN_BISECT_MIRROR="$DEBIAN_BISECT_MIRROR"
fi


# either execute $script as a script from $PATH or as a shell snippet
ret=0
if [ -x "$script" ] || echo "$script" | grep --invert-match --silent --perl-regexp '[^\w@\%+=:,.\/-]'; then
	"$script" "$TMPDIR/config" || ret=$?
else
	sh -c "$script" exec "$TMPDIR/config" || ret=$?
fi

# since we installed systemd-sysv, systemctl is available
ssh -F "$TMPDIR/config" qemu systemctl poweroff

wait $QEMUPID

trap - EXIT

showqemulog
cleantmp

if [ "$ret" -eq 0 ]; then
	exit 0
else
	exit 1
fi
