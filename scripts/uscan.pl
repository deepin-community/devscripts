#!/usr/bin/perl
# -*- tab-width: 8; indent-tabs-mode: t; cperl-indent-level: 4 -*-
# vim: set ai shiftwidth=4 tabstop=4 expandtab:

# uscan: This program looks for watch files and checks upstream ftp sites
# for later versions of the software.
#
# Originally written by Christoph Lameter <clameter@debian.org> (I believe)
# Modified by Julian Gilbey <jdg@debian.org>
# HTTP support added by Piotr Roszatycki <dexter@debian.org>
# Rewritten in Perl, Copyright 2002-2006, Julian Gilbey
# Rewritten in Object Oriented Perl, copyright 2018, Xavier Guimard
# <yadd@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

#######################################################################
# {{{ code 0: POD for manpage
#######################################################################

=pod

=head1 NAME

uscan - scan/watch upstream sources for new releases of software

=head1 SYNOPSIS

B<uscan> [I<options>] [I<path>]

=head1 DESCRIPTION

For basic usage, B<uscan> is executed without any arguments from the root
of the Debianized source tree where you see the F<debian/> directory, or
a directory containing multiple source trees.

Unless --watchfile is given, B<uscan> looks recursively for valid source
trees starting from the current directory (see the below section
L<Directory name checking> for details).

For each valid source tree found, typically the following happens:

=over

=item * B<uscan> reads the first entry in F<debian/changelog> to determine the
source package name I<< <spkg> >> and the last upstream version.

=item * B<uscan> process the watch lines F<debian/watch> from the top to the
bottom in a single pass.

=over

=item * B<uscan> downloads a web page from the specified I<URL> in
F<debian/watch>.

=item * B<uscan> extracts hrefs pointing to the upstream tarball(s) from the
web page using the specified I<matching-pattern> in F<debian/watch>.

=item * B<uscan> downloads the upstream tarball with the highest version newer
than the last upstream version.

=item * B<uscan> saves the downloaded tarball to the parent B<../> directory:
I<< ../<upkg>-<uversion>.tar.gz >>

=item * B<uscan> invokes B<mk-origtargz> to create the source tarball: I<<
../<spkg>_<oversion>.orig.tar.gz >>

=over

=item * For a multiple upstream tarball (MUT) package, the secondary upstream
tarball will instead be named I<< ../<spkg>_<oversion>.orig-<component>.tar.gz >>.

=back

=item * Repeat until all lines in F<debian/watch> are processed.

=back

=item * B<uscan> invokes B<uupdate> to create the Debianized source tree: I<<
../<spkg>-<oversion>/* >>

=back

Please note the following.

=over

=item * For simplicity, the compression method used in examples is B<gzip> with
B<.gz> suffix.  Other methods such as B<xz>, B<bzip2>, and B<lzma> with
corresponding B<xz>, B<bz2> and B<lzma> suffixes may also be used.

=item * Since version 4 of debian/watch, B<uscan> enables handling of multiple
upstream tarball (MUT) packages but this is a rare case for Debian packaging.
For a single upstream tarball package, there is only one watch line and no
I<< ../<spkg>_<oversion>.orig-<component>.tar.gz >>.

=item * B<uscan> with the B<--verbose> option produces a human readable report
of B<uscan>'s execution.

=item * B<uscan> with the B<--debug> option produces a human readable report of
B<uscan>'s execution including internal variable states.

=item * B<uscan> with the B<--extra-debug> option produces a human readable
report of B<uscan>'s execution including internal variable states and remote
content during "search" step.

=item * B<uscan> with the B<--dehs> option produces an upstream package status
report in XML format for other programs such as the Debian External Health
System.

=item * The primary objective of B<uscan> is to help identify if the latest
version upstream tarball is used or not; and to download the latest upstream
tarball.  The ordering of versions is decided by B<dpkg --compare-versions>.

=item * B<uscan> with the B<--safe> option limits the functionality of B<uscan>
to its primary objective.  Both the repacking of downloaded files and
updating of the source tree are skipped to avoid running unsafe scripts.
This also changes the default to B<--no-download> and B<--skip-signature>.

=back

=head1 FORMAT OF THE WATCH FILE

The current debian/watch format is described in L<debian-watch(5)> manpage.
Old formats I<(version 1 to 4)> are described in L<debian-watch-4(5)> manpage.

=head1 COPYRIGHT FILE EXAMPLES

Here is an example for the F<debian/copyright> file which initiates automatic
repackaging of the upstream tarball into I<< <spkg>_<oversion>.orig.tar.gz >>
(In F<debian/copyright>, the B<Files-Excluded> and
B<Files-Excluded->I<component> stanzas are a part of the first paragraph and
there is a blank line before the following paragraphs which contain B<Files>
and other stanzas.):

  Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
  Files-Excluded: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js

  Files: *
  Copyright: ...
  ...

Here is another example for the F<debian/copyright> file which initiates
automatic repackaging of the multiple upstream tarballs into
I<< <spkg>_<oversion>.orig.tar.gz >> and
I<< <spkg>_<oversion>.orig-bar.tar.gz >>:

  Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
  Files-Excluded: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js
  Files-Excluded-bar: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js

  Files: *
  Copyright: ...
  ...

The F<debian/copyright> file may also contain B<Files-Included> and
B<Files-Included->I<component> stanzas which include files that were
previously excluded. This is useful to exclude most but not all files
in a directory:

  Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
  Files-Excluded: vendor-dir
  Files-Included:
   vendor-dir/directory/to/keep
   vendor-dir/*/file-to-keep

  Files: *
  Copyright: ...
  ...

See mk-origtargz(1).

=head1 KEYRING FILE EXAMPLES

Let's assume that the upstream "B<< uscan test key (no secret)
<none@debian.org> >>" signs its package with a secret OpenPGP key and publishes
the corresponding public OpenPGP key.  This public OpenPGP key can be
identified in 3 ways using the hexadecimal form.

=over

=item * The fingerprint as the 20 byte data calculated from the public OpenPGP
key. E.  g., 'B<CF21 8F0E 7EAB F584 B7E2 0402 C77E 2D68 7254 3FAF>'

=item * The long keyid as the last 8 byte data of the fingerprint. E. g.,
'B<C77E2D6872543FAF>'

=item * The short keyid is the last 4 byte data of the fingerprint. E. g.,
'B<72543FAF>'

=back

Considering the existence of the collision attack on the short keyid, the use
of the long keyid is recommended for receiving keys from the public key
servers.  You must verify the downloaded OpenPGP key using its full fingerprint
value which you know is the trusted one.

The armored keyring file F<debian/upstream/signing-key.asc> can be created by
using the B<gpg> command as follows.

  $ gpg --recv-keys "C77E2D6872543FAF"
  ...
  $ gpg --finger "C77E2D6872543FAF"
  pub   4096R/72543FAF 2015-09-02
        Key fingerprint = CF21 8F0E 7EAB F584 B7E2  0402 C77E 2D68 7254 3FAF
  uid                  uscan test key (no secret) <none@debian.org>
  sub   4096R/52C6ED39 2015-09-02
  $ cd path/to/<upkg>-<uversion>
  $ mkdir -p debian/upstream
  $ gpg --export --export-options export-minimal --armor \
        'CF21 8F0E 7EAB F584 B7E2  0402 C77E 2D68 7254 3FAF' \
        >debian/upstream/signing-key.asc

The binary keyring files, F<debian/upstream/signing-key.pgp> and
F<debian/upstream-signing-key.pgp>, are still supported but deprecated.

If a group of developers sign the package, you need to list fingerprints of all
of them in the argument for B<gpg --export ...> to make the keyring to contain
all OpenPGP keys of them.

Sometimes you may wonder who made a signature file.  You can get the public
keyid used to create the detached signature file F<foo-2.0.tar.gz.asc> by
running B<gpg> as:

  $ gpg -vv foo-2.0.tar.gz.asc
  gpg: armor: BEGIN PGP SIGNATURE
  gpg: armor header: Version: GnuPG v1
  :signature packet: algo 1, keyid C77E2D6872543FAF
  	version 4, created 1445177469, md5len 0, sigclass 0x00
  	digest algo 2, begin of digest 7a c7
  	hashed subpkt 2 len 4 (sig created 2015-10-18)
  	subpkt 16 len 8 (issuer key ID C77E2D6872543FAF)
  	data: [4091 bits]
  gpg: assuming signed data in `foo-2.0.tar.gz'
  gpg: Signature made Sun 18 Oct 2015 11:11:09 PM JST using RSA key ID 72543FAF
  ...

=head1 COMMANDLINE OPTIONS

For the basic usage, B<uscan> does not require to set these options.

=over

=item B<--conffile>, B<--conf-file>

Add or replace default configuration files (C</etc/devscripts.conf> and
C<~/.devscripts>). This can only be used as the first option given on the
command-line.

=over

=item replace:

  uscan --conf-file test.conf --verbose

=item add:

  uscan --conf-file +test.conf --verbose

If one B<--conf-file> has no C<+>, default configuration files are ignored.

=back

=item B<--no-conf>, B<--noconf>

Don't read any configuration files. This can only be used as the first option
given on the command-line.

=item B<--no-verbose>

Don't report verbose information. (default)

=item B<--verbose>, B<-v>

Report verbose information.

=item B<--debug>, B<-vv>

Report verbose information and some internal state values.

=item B<--extra-debug>, B<-vvv>

Report verbose information including the downloaded
web pages as processed to STDERR for debugging.

=item B<--dehs>

Send DEHS style output (XML-type) to STDOUT, while
send all other uscan output to STDERR.

=item B<--no-dehs>

Use only traditional uscan output format. (default)

=item B<--download>, B<-d>

Download the new upstream release. (default)

=item B<--force-download>, B<-dd>

Download the new upstream release even if up-to-date. (may not overwrite the local file)

=item B<--overwrite-download>, B<-ddd>

Download the new upstream release even if up-to-date. (may overwrite the local file)

=item B<--no-download>, B<--nodownload>

Don't download and report information.

Previously downloaded tarballs may be used.

Change default to B<--skip-signature>.

=item B<--signature>

Download signature. (default)

=item B<--no-signature>

Don't download signature but verify if already downloaded.

=item B<--skip-signature>

Don't bother download signature nor verifying signature.

=item B<--safe>, B<--report>

Avoid running unsafe scripts by skipping both the repacking of the downloaded
package and the updating of the new source tree.

Change default to B<--no-download> and B<--skip-signature>.

When the objective of running B<uscan> is to gather the upstream package status
under the security conscious environment, please make sure to use this option.

=item B<--report-status>

This is equivalent of setting "B<--verbose --safe>".

=item B<--download-version> I<version>

Specify the I<version> which the upstream release must match in order to be
considered, rather than using the release with the highest version.
(a best effort feature)

=item B<--download-debversion> I<version>

Specify the Debian package version to download the corresponding upstream
release version.  The B<dversionmangle> and B<uversionmangle> rules are considered.
(a best effort feature)

=item B<--download-current-version>

Download the currently packaged version.
(a best effort feature)

=item B<--check-dirname-level> I<N>

See the below section L<Directory name checking> for an explanation of this option.

=item B<--check-dirname-regex> I<regex>

See the below section L<Directory name checking> for an explanation of this option.

=item B<--destdir> I<path>
Normally, B<uscan> changes its internal current directory to the package's
source directory where the F<debian/> is located.  Then the destination
directory for the downloaded tarball and other files is set to the parent
directory F<../> from this internal current directory.

This default destination directory can be overridden by setting B<--destdir>
option to a particular I<path>.  If this I<path> is a relative path, the
destination directory is determined in relative to the internal current
directory of B<uscan> execution. If this I<path> is a absolute path, the
destination directory is set to I<path> irrespective of the internal current
directory of B<uscan> execution.

The above is true not only for the simple B<uscan> run in the single source tree
but also for the advanced scanning B<uscan> run with subdirectories holding
multiple source trees.

One exception is when B<--watchfile> and B<--package> are used together.  For
this case, the internal current directory of B<uscan> execution and the default
destination directory are set to the current directory F<.> where B<uscan> is
started.  The default destination directory can be overridden by setting
B<--destdir> option as well.

=item B<--package> I<package>

Specify the name of the package to check for rather than examining
F<debian/changelog>; this requires the B<--upstream-version> (unless a version
is specified in the F<watch> file) and B<--watchfile> options as well.
Furthermore, no directory scanning will be done and nothing will be downloaded.
This option automatically sets B<--no-download> and B<--skip-signature>; and
probably most useful in conjunction with the DEHS system (and B<--dehs>).

=item B<--upstream-version> I<upstream-version>

Specify the current upstream version rather than examine F<debian/watch> or
F<debian/changelog> to determine it. This is ignored if a directory scan is being
performed and more than one F<debian/watch> file is found.

=item B<--vcs-export-uncompressed>

Disable compression of tarballs exported from a version control system
(Git or Subversion). This takes more space, but saves time if
B<mk-origtargz> must repack the tarball to exclude files. It forces
repacking of all exported tarballs.

=item B<--watchfile> I<watchfile>

Specify the I<watchfile> rather than perform a directory scan to determine it.
If this option is used without B<--package>, then B<uscan> must be called from
within the Debian package source tree (so that F<debian/changelog> can be found
simply by stepping up through the tree).

One exception is when B<--watchfile> and B<--package> are used together.
B<uscan> can be called from anywhare and the internal current directory of
B<uscan> execution and the default destination directory are set to the current
directory F<.> where B<uscan> is started.

See more in the B<--destdir> explanation.

=item B<--bare>

Disable all site specific special case codes to perform URL redirections and
page content alterations.

=item B<--http-header>

Add specified header in HTTP requests for matching url. This option can be used
more than one time, values must be in the form "baseUrl@Name=value. Example:

  uscan --http-header https://example.org@My-Token=qwertyuiop

Security:

=over

=item The given I<baseUrl> must exactly match the base url before '/'.
Examples:

  |        --http-header value         |           Good for          | Never used |
  +------------------------------------+-----------------------------+------------+
  | https://example.org.com@Hdr=Value  | https://example.org.com/... |            |
  | https://example.org.com/@Hdr=Value |                             |     X      |
  | https://e.com:1879@Hdr=Value       | https://e.com:1879/...      |            |
  | https://e.com:1879/dir@Hdr=Value   | https://e.com:1879/dir/...  |            |
  | https://e.com:1879/dir/@Hdr=Value  |                             |     X      |

=item It is strongly recommended to not use this feature to pass a secret
token over unciphered connection I<(http://)>

=item You can use C<USCAN_HTTP_HEADER> variable (in C<~/.devscripts>) to hide
secret token from scripts

=back

=item B<--no-exclusion>

Don't automatically exclude files mentioned in F<debian/copyright> field B<Files-Excluded>.

=item B<--no-symlink>

Don't rename nor repack upstream tarball.

=item B<--timeout> I<N>

Set timeout to I<N> seconds (default 20 seconds).

=item B<--user-agent>, B<--useragent>

Override the default user agent header.

=item B<--help>

Give brief usage information.

=item B<--version>

Display version information.

=back

B<uscan> also accepts following options and passes them to B<mk-origtargz>:

=over

=item B<--symlink>

Make B<orig.tar.gz> (with the appropriate extension) symlink to the downloaded
files. (This is the default behavior.)

=item B<--copy>

Instead of symlinking as described above, copy the downloaded files.

=item B<--rename>

Instead of symlinking as described above, rename the downloaded files.

=item B<--repack>

After having downloaded an lzma tar, xz tar, bzip tar, gz tar, lz tar, zip, jar,
xpi, zstd archive, repack it to the specified compression
(see B<--compression>).

The unzip package must be installed in order to repack zip, jar, and xpi
archives, the xz-utils package must be installed to repack lzma or xz tar
archives, zstd must be installed to repack zstd archives, and lzip must be
installed to repack lz tar archives.

=item B<--compression> [ B<gzip> | B<bzip2> | B<lzma> | B<xz> ]

In the case where the upstream sources are repacked (either because B<--repack>
option is given or F<debian/copyright> contains the field B<Files-Excluded>),
it is possible to control the compression method via the parameter.  The
default is B<gzip> for normal tarballs, and B<xz> for tarballs generated
directly from the git repository.

=item B<--copyright-file> I<copyright-file>

Exclude files mentioned in B<Files-Excluded> in the given I<copyright-file>.
This is useful when running B<uscan> not within a source package directory.

=back

=head1 DEVSCRIPT CONFIGURATION VARIABLES

For the basic usage, B<uscan> does not require to set these configuration
variables.

The two configuration files F</etc/devscripts.conf> and F<~/.devscripts> are
sourced by a shell in that order to set configuration variables. These
may be overridden by command line options. Environment variable settings are
ignored for this purpose. If the first command line option given is
B<--noconf>, then these files will not be read. The currently recognized
variables are:

=over

=item B<USCAN_DOWNLOAD>

Download or report only:

=over

=item B<no>: equivalent to B<--no-download>, newer upstream files will
not be downloaded.

=item B<yes>: equivalent to B<--download>, newer upstream files will
be downloaded. This is the default behavior.

See also B<--force-download> and B<--overwrite-download>.

=back

=item B<USCAN_SAFE>

If this is set to B<yes>, then B<uscan> avoids running unsafe scripts by
skipping both the repacking of the downloaded package and the updating of the
new source tree; this is equivalent to the B<--safe> options; this also sets
the default to B<--no-download> and B<--skip-signature>.

=item B<USCAN_TIMEOUT>

If set to a number I<N>, then set the timeout to I<N> seconds. This is
equivalent to the B<--timeout> option.

=item B<USCAN_SYMLINK>

If this is set to no, then a I<pkg>_I<version>B<.orig.tar.{gz|bz2|lzma|xz}>
symlink will not be made (equivalent to the B<--no-symlink> option). If it is
set to B<yes> or B<symlink>, then the symlinks will be made. If it is set to
B<rename>, then the files are renamed (equivalent to the B<--rename> option).

=item B<USCAN_DEHS_OUTPUT>

If this is set to B<yes>, then DEHS-style output will be used. This is
equivalent to the B<--dehs> option.

=item B<USCAN_VERBOSE>

If this is set to B<yes>, then verbose output will be given.  This is
equivalent to the B<--verbose> option.

=item B<USCAN_USER_AGENT>

If set, the specified user agent string will be used in place of the default.
This is equivalent to the B<--user-agent> option.

=item B<USCAN_DESTDIR>

If set, the downloaded files will be placed in this  directory.  This is
equivalent to the B<--destdir> option.

=item B<USCAN_REPACK>

If this is set to yes, then after having downloaded a bzip tar, lzma tar, xz
tar, zip or zstd archive, uscan will repack it to the specified compression
(see B<--compression>). This is equivalent to the B<--repack> option.

=item B<USCAN_EXCLUSION>

If this is set to no, files mentioned in the field B<Files-Excluded> of
F<debian/copyright> will be ignored and no exclusion of files will be tried.
This is equivalent to the B<--no-exclusion> option.

=item B<USCAN_HTTP_HEADER>

If set, the specified http header will be used if URL match. This is equivalent
to B<--http-header> option.

=item B<USCAN_VCS_EXPORT_UNCOMPRESSED>

If this is set to yes, tarballs exported from a version control system
will not be compressed. This is equivalent to the
B<--vcs-export-uncompressed> option.

=back

=head1 EXIT STATUS

The exit status gives some indication of whether a newer version was found or
not; one is advised to read the output to determine exactly what happened and
whether there were any warnings to be noted.

=over

=item B<0>

Either B<--help> or B<--version> was used, or for some F<watch> file which was
examined, a newer upstream version was located.

=item B<1>

No newer upstream versions were located for any of the F<watch> files examined.

=back

=head1 ADVANCED FEATURES

B<uscan> has many other enhanced features which are skipped in the above
section for the simplicity.  Let's check their highlights.

B<uscan> can be executed with I<path> as its argument to change the starting
directory of search from the current directory to I<path> .

If you are not sure what exactly is happening behind the scene, please enable
the B<--verbose> option.  If this is not enough, enable the B<--debug> option
too see all the internal activities.

See L<COMMANDLINE OPTIONS> and L<DEVSCRIPT CONFIGURATION VARIABLES> for other
variations.

=head2 Custom script

The optional I<script> parameter in F<debian/watch> means to execute I<script>
with options after processing this line if specified.

See L<HISTORY AND UPGRADING> for how B<uscan> invokes the custom I<script>.

For compatibility with other tools such as B<git-buildpackage>, it may not be
wise to create custom scripts with random behavior.  In general, B<uupdate> is
the best choice for the non-native package and custom scripts, if created,
should behave as if B<uupdate>.  For possible use case, see
L<http://bugs.debian.org/748474> as an example.

=head2 URL diversion

Some popular web sites changed their web page structure causing maintenance
problems to the watch file.  There are some redirection services created to
ease maintenance of the watch file.  Currently, B<uscan> makes automatic
diversion of URL requests to the following URLs to cope with this situation.

=over

=item * L<http://sf.net>

=item * L<http://pypi.python.org>

=back

=head2 Directory name checking

Similarly to several other scripts in the B<devscripts> package, B<uscan>
explores the requested directory trees looking for F<debian/changelog> and
F<debian/watch> files. As a safeguard against stray files causing potential
problems, and in order to promote efficiency, it will examine the name of the
parent directory once it finds the F<debian/changelog> file, and check that the
directory name corresponds to the package name. It will only attempt to
download newer versions of the package and then perform any requested action if
the directory name matches the package name. Precisely how it does this is
controlled by two configuration file variables
B<DEVSCRIPTS_CHECK_DIRNAME_LEVEL> and B<DEVSCRIPTS_CHECK_DIRNAME_REGEX>, and
their corresponding command-line options B<--check-dirname-level> and
B<--check-dirname-regex>.

B<DEVSCRIPTS_CHECK_DIRNAME_LEVEL> can take the following values:

=over

=item B<0>

Never check the directory name.

=item B<1>

Only check the directory name if we have had to change directory in
our search for F<debian/changelog>, that is, the directory containing
F<debian/changelog> is not the directory from which B<uscan> was invoked.
This is the default behavior.

=item B<2>

Always check the directory name.

=back

The directory name is checked by testing whether the current directory name (as
determined by pwd(1)) matches the regex given by the configuration file
option B<DEVSCRIPTS_CHECK_DIRNAME_REGEX> or by the command line option
B<--check-dirname-regex> I<regex>. Here regex is a Perl regex (see
perlre(3perl)), which will be anchored at the beginning and the end. If regex
contains a B</>, then it must match the full directory path. If not, then
it must match the full directory name. If regex contains the string I<package>,
this will be replaced by the source package name, as determined from the
F<debian/changelog>. The default value for the regex is: I<package>B<(-.+)?>, thus matching
directory names such as I<package> and I<package>-I<version>.

=head1 HISTORY AND UPGRADING

This section briefly describes the backwards-incompatible F<watch> file features
which have been added in each F<watch> file version, and the first version of the
B<devscripts> package which understood them.

=over

=item Pre-version 2

The F<watch> file syntax was significantly different in those days. Don't use it.
If you are upgrading from a pre-version 2 F<watch> file, you are advised to read
this manpage and to start from scratch.

=item Version 2

B<devscripts> version 2.6.90: The first incarnation of the current style of
F<watch> files. This version is also deprecated and will be rejected after
the Debian 11 release.

=item Version 3

B<devscripts> version 2.8.12: Introduced the following: correct handling of
regex special characters in the path part, directory/path pattern matching,
version number in several parts, version number mangling. Later versions
have also introduced URL mangling.

If you are upgrading from version 2, the key incompatibility is if you have
multiple groups in the pattern part; whereas only the first one would be used
in version 2, they will all be used in version 3. To avoid this behavior,
change the non-version-number groups to be B<(?:> I< ...> B<)> instead of a
plain B<(> I< ... > B<)> group.

=over

=item * B<uscan> invokes the custom I<script> as "I<script> B<--upstream-version>
I<version> B<../>I<spkg>B<_>I<version>B<.orig.tar.gz>".

=item * B<uscan> invokes the standard B<uupdate> as "B<uupdate> B<--no-symlink
--upstream-version> I<version> B<../>I<spkg>B<_>I<version>B<.orig.tar.gz>".

=back

=item Version 4

B<devscripts> version 2.15.10: The first incarnation of F<watch> files
supporting multiple upstream tarballs.

The syntax of the watch file is relaxed to allow more spaces for readability.

If you have a custom script in place of B<uupdate>, you may also encounter
problems updating from Version 3.

=over

=item * B<uscan> invokes the custom I<script> as "I<script> B<--upstream-version>
I<version>".

=item * B<uscan> invokes the standard B<uupdate> as "B<uupdate> B<--find>
B<--upstream-version> I<version>".

=back

Restriction for B<--dehs> is lifted by redirecting other output to STDERR when
it is activated.

=back

=head1 SEE ALSO

dpkg(1), mk-origtargz(1), perlre(1), uupdate(1), devscripts.conf(5)

=head1 AUTHOR

The original version of uscan was written by Christoph Lameter
<clameter@debian.org>. Significant improvements, changes and bugfixes were
made by Julian Gilbey <jdg@debian.org>. HTTP support was added by Piotr
Roszatycki <dexter@debian.org>. The program was rewritten in Perl by Julian
Gilbey. Xavier Guimard converted it in object-oriented Perl using L<Moo>.

=cut

#######################################################################
# }}} code 0: POD for manpage
#######################################################################
#######################################################################
# {{{ code 1: initializer, command parser, and loop over watchfiles
#######################################################################

# This code block is the start up of uscan.
# Actual processing is performed by process_watchfile in the next block
#
# This has 3 different modes to process watchfiles
#
#  * If $opt_watchfile and $opt_package are defined, test specified watchfile
#    without changelog (sanity check for $opt_uversion may be good idea)
#  * If $opt_watchfile is defined but $opt_package isn't defined, test specified
#    watchfile assuming you are in source tree and debian/changelogis used to
#    set variables
#  * If $opt_watchfile isn't defined, scan subdirectories of directories
#    specified as ARGS (if none specified, "." is scanned).
#    * Normal packaging has no ARGS and uses "."
#    * Archive status scanning tool uses many ARGS pointing to the expanded
#      source tree to be checked.
# Comments below focus on Normal packaging case and sometimes ignores first 2
# watch file testing setup.

use 5.010;    # defined-or (//)
use strict;
use warnings;
use Devscripts::Uscan;
use Devscripts::Uscan::Output;

our $uscan_version = "###VERSION###";

BEGIN {
    pop @INC if $INC[-1] eq '.';
}

uscan_verbose "$progname (version $uscan_version) See $progname(1) for help";

my ($res, $found) = uscan();

# Are there any warnings to give if we're using dehs?
$dehs_end_output = 1;
dehs_output if ($dehs);

exit($res ? $res : $found ? 0 : 1);
