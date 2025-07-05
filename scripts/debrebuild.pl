#!/usr/bin/perl
#
# Copyright © 2014-2024 Johannes Schauer Marin Rodrigues <josch@debian.org>
# Copyright © 2020      Niels Thykier <niels@thykier.net>
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

use strict;
use warnings;
use autodie;

use Getopt::Long qw(:config gnu_getopt no_bundling no_auto_abbrev);

use Dpkg::Control;
use Dpkg::Control::FieldsCore;
use Dpkg::Index;
use Dpkg::Deps;
use Dpkg::Source::Package;
use Dpkg::Version;
use File::Temp qw(tempfile tempdir);
use File::Path qw(make_path);
use File::HomeDir;
use JSON::PP;
use Time::Piece;
use File::Basename;
use File::Spec;
use List::Util qw(any none);
use English;

my $progname;

BEGIN {
    $progname = basename($0);
    eval { require String::ShellQuote; };
    if ($@) {
        if ($@ =~ /^Can\'t locate String\/ShellQuote\.pm/) {
            die
"$progname: you must have the libstring-shellquote-perl package installed\n"
              . "to use this script";
        } else {
            die
"$progname: problem loading the String::ShellQuote module:\n  $@\n"
              . "Have you installed the libstring-shellquote-perl package?";
        }
    }

    eval {
        require LWP::Simple;
        require LWP::UserAgent;
        require URI::Escape;    # libwww-perl depends on liburi-perl
        no warnings;
        $LWP::Simple::ua
          = LWP::UserAgent->new(agent => 'LWP::UserAgent/debrebuild');
        $LWP::Simple::ua->env_proxy();
    };
    if ($@) {
        if ($@ =~ m/Can\'t locate LWP/) {
            die "$progname: you must have the libwww-perl package installed\n"
              . "to use this script";
        } else {
            die "$progname: problem loading the LWP and URI modules:\n  $@\n"
              . "Have you installed the libwww-perl package?";
        }
    }

}

# Make sure that each print statement flushes standard output.
# This avoid having to manually flush when printing strings that do not end
# in a newline.
STDOUT->autoflush(1);

my $respect_build_path = 1;
my $use_tor            = 0;
my $outdir             = './';
my $builder            = 'none';
my $cache;

my %OPTIONS = (
    'help|h'              => sub { usage(0); },
    'use-tor-proxy!'      => \$use_tor,
    'respect-build-path!' => \$respect_build_path,
    'buildresult=s'       => \$outdir,
    'builder=s'           => \$builder,
    'cache=s'             => \$cache,
);

sub usage {
    my ($exit_code) = @_;
    $exit_code //= 0;
    print <<EOF;
Usage: $progname [options] <buildinfo>
       $progname <--help|-h>

Given a buildinfo file, builds the referenced source package in an environment
documented in the provided buildinfo file. The build can be performed by
sbuild or other builders in a chroot environment created by debootsnap.  The
generated artifacts will be verified against the hashes from the buildinfo
file.

Options:
 --help, -h                 Show this help and exit
 --[no-]use-tor-proxy       Whether to fetch resources via tor (socks://127.0.0.1:9050)
                            Assumes "apt-transport-tor" is installed both in host + chroot
 --[no-]respect-build-path  Whether to setup the build to use the Build-Path from the
                            provided .buildinfo file.
 --buildresult              Directory for the build artifacts (default: ./)
 --builder=BUILDER          Which building software should be used. Possible values are
                            none, sbuild, mmdebstrap, dpkg and sbuild+unshare. The default
                            is none. See section BUILDER for details.

Note: $progname can parse buildinfo files with and without a GPG signature.  However,
the signature (if present) is discarded as debrebuild does not support verifying
it.  If the authenticity or integrity of the buildinfo files are important to
you, checking these need to be done before invoking $progname, for example by using
dscverify.

EXAMPLES

    \$ $progname --buildresult=./artifacts --builder=mmdebstrap hello_2.10-2_amd64.buildinfo

BUILDERS

debrebuild can use different backends to perform the actual package rebuild.
The desired backend is chosen using the --builder option. The default is
"none".

    none            Dry-run mode. No build is performed.
    sbuild          Use sbuild to build the package. This requires sbuild to be
                    setup with schroot chroots of Debian stable distributions.
    mmdebstrap      Use mmdebstrap to build the package. This requires no
                    setup and no superuser privileges.
    dpkg            Directly run apt-get and dpkg-buildpackage on the current
                    system without chroot. This requires root privileges.
    sbuild+unshare  Use sbuild with the unshare backend. This will create the
                    chroot and perform the build without superuser privileges
                    and without any setup.

UNSHARE

Before kernel 5.10.1 or before Debian 11 (Bullseye), unprivileged user
namespaces were disabled in Debian for security reasons. Refer to Debian bug
#898446 for details. To enable user namespaces, run:

    \$ sudo sysctl -w kernel.unprivileged_userns_clone=1

The sbuild+unshare builder requires and the mmdebstrap builder benefits from
having unprivileged user namespaces activated. On Ubuntu they are enabled by
default.

LIMITATIONS

Currently, the code assumes that all packages were at some point part of Debian
unstable main. This fails for packages from Debian ports, packages from
experimental as well as for locally built packages or packages from third
party repositories. Enabling support for Debian ports and experimental is
conceptually possible and only needs somebody implementing it.

EOF

    exit($exit_code);
}

GetOptions(%OPTIONS) or usage(1);

my $buildinfo = shift @ARGV;
if (not defined($buildinfo)) {
    print STDERR "ERROR: Missing mandatory buildinfo filename\n";
    print STDERR "\n";
    usage(1);
}
if ($buildinfo eq '--help' or $buildinfo eq '-h') {
    usage(0);
}

if ($buildinfo =~ m/^-/) {
    print STDERR "ERROR: Unsupported option $buildinfo\n";
    print STDERR "\n";
    usage(1);
}

if (@ARGV) {
    print STDERR "ERROR: This program requires exactly argument!\n";
    print STDERR "\n";
    usage(1);
}

my $base_mirror = "http://snapshot.debian.org/archive/debian";
if ($use_tor) {
    $base_mirror = "tor+http://snapshot.debian.org/archive/debian";
    eval {
        $LWP::Simple::ua->proxy([qw(http https)] => 'socks://127.0.0.1:9050');
    };
    if ($@) {
        if ($@ =~ m/Can\'t locate LWP/) {
            die
"Unable to use tor: the liblwp-protocol-socks-perl package is not installed\n";
        } else {
            die "Unable to use tor: Couldn't load socks proxy support: $@\n";
        }
    }
}

# buildinfo support in libdpkg-perl (>= 1.18.11)
my $cdata = Dpkg::Control->new(type => CTRL_FILE_BUILDINFO, allow_pgp => 1);

if (not $cdata->load($buildinfo)) {
    die "cannot load $buildinfo\n";
}

if ($cdata->get_option('is_pgp_signed')) {
    print(
        "$buildinfo contains a GPG signature which has NOT been validated\n");
} else {
    print "$buildinfo was unsigned\n";
}

my @architectures = split /\s+/, $cdata->{"Architecture"};
my $build_source  = (scalar(grep /^source$/, @architectures)) == 1;
my $build_archall = (scalar(grep /^all$/,    @architectures)) == 1;
@architectures = grep { !/^source$/ && !/^all$/ } @architectures;
if (scalar @architectures > 1) {
    die "more than one architecture in Architecture field\n";
}
my $build_archany = (scalar @architectures) == 1;

my $build_arch = $cdata->{"Build-Architecture"};
if (not defined($build_arch)) {
    die "need Build-Architecture field\n";
}
my $host_arch = $cdata->{"Host-Architecture"};
if (not defined($host_arch)) {
    $host_arch = $build_arch;
}

my $srcpkgname = $cdata->{Source};
my $srcpkgver  = $cdata->{Version};

# in some cases the source field contains a version in the form: name (version)
# for example: binclock (1.5-6)
if ($srcpkgname =~ / /) {
    # make $@ local, so we don't print "Undefined subroutine" error message
    # in other parts where we evaluate $@
    local $@ = '';
    # field_parse_binary_source is only available starting with dpkg 1.21.0
    eval { ($srcpkgname, $srcpkgver) = field_parse_binary_source($cdata); };
    if ($@) {
        ($srcpkgname, $srcpkgver) = split / /, $srcpkgname, 2;
        # Add a simple control check to avoid the worst surprises and stop
        # obvious cases of garbage-in-garbage-out.
        die("Unexpected source package name: ${srcpkgname}\n")
          if $srcpkgname =~ m{[ \t_/\(\)<>!\n%&\$\#\@]};
        # remove the surrounding parenthesis from the version
        $srcpkgver =~ s/^\((.*)\)$/$1/;
    }
}

if (!defined $srcpkgname) {
    die "unable to obtain source package name from buildinfo\n";
}
if (!defined $srcpkgver) {
    die "unable to obtain source package version from buildinfo\n";
}

my $srcpkgbinver
  = $cdata->{Version};    # this version will include the binmu suffix
$srcpkgbinver =~ s/^\d+://;

my $new_buildinfo;
{
    my $arch;
    if ($build_archany) {
        $arch = $host_arch;
    } elsif ($build_archall) {
        $arch = 'all';
    } else {
        die "nothing to build\n";
    }
    $new_buildinfo = "$outdir/${srcpkgname}_${srcpkgbinver}_$arch.buildinfo";
}
if (-e $new_buildinfo) {
    my ($dev1, $ino1) = (lstat $buildinfo)[0, 1]
      or die "cannot lstat $buildinfo: $!\n";
    my ($dev2, $ino2) = (lstat $new_buildinfo)[0, 1]
      or die "cannot lstat $new_buildinfo: $!\n";
    if ($dev1 == $dev2 && $ino1 == $ino2) {
        die(    "E: refusing to overwrite the input buildinfo file\n"
              . "E: Either pass an output directory via --buildresult "
              . "or call debrebuild from a directory that does not include $buildinfo"
        );
    }
}

my $inst_build_deps = $cdata->{"Installed-Build-Depends"};
if (not defined($inst_build_deps)) {
    die "need Installed-Build-Depends field\n";
}
my $custom_build_path = $respect_build_path ? $cdata->{'Build-Path'} : undef;

if (defined($custom_build_path)) {
    if ($custom_build_path =~ m{['`\$\\"\(\)<>#]|(?:\a|/)[.][.](?:\z|/)}) {
        warn(
"Retry build with --no-respect-build-path to ignore the Build-Path field.\n"
        );
        die(
"Refusing to use $custom_build_path as Build-Path: Looks too special to be true"
        );
    }

    if ($custom_build_path eq '' or $custom_build_path !~ m{^/}) {
        warn(
"Retry build with --no-respect-build-path to ignore the Build-Path field.\n"
        );
        die(
qq{Build-Path must be a non-empty absolute path (i.e. start with "/").\n}
        );
    }
    print "Using defined Build-Path: ${custom_build_path}\n";
} else {
    if ($respect_build_path) {
        print
"No Build-Path defined; not setting a defined build path for this build.\n";
    }
}

my $srcpkg = Dpkg::Source::Package->new();
$srcpkg->{fields}{'Source'}  = $srcpkgname;
$srcpkg->{fields}{'Version'} = $srcpkgver;
my $dsc_fname
  = (dirname($buildinfo)) . '/' . $srcpkg->get_basename(1) . ".dsc";

my $debsnapexe = 'debsnap';
if ($PROGRAM_NAME eq "scripts/debrebuild.pl" && -x "scripts/debsnap.pl") {
    $debsnapexe = "scripts/debsnap.pl";
}

if (!-e $dsc_fname) {
    print(  "I: obtaining dsc using: $debsnapexe --force"
          . " --destdir . $srcpkgname $srcpkgver\n");
    0 == system $debsnapexe, '--force', '--verbose', '--destdir',
      dirname($buildinfo), $srcpkgname, $srcpkgver
      or die "$debsnapexe failed\n";
}
if (!-e $dsc_fname) {
    die(    "$debsnapexe failed to download "
          . $srcpkg->get_basename(1)
          . ".dsc\n");
}

print "I: verifying dsc...";
my $buildinfo_checksums = Dpkg::Checksums->new();
$buildinfo_checksums->add_from_control($cdata);
$buildinfo_checksums->add_from_file($dsc_fname,
    key => $srcpkg->get_basename(1) . ".dsc");
print " successful!\n";

my $environment = $cdata->{"Environment"};
if (not defined($environment)) {
    die "need Environment field\n";
}
$environment =~ s/\n/ /g;    # remove newlines
$environment =~ s/^ //;      # remove leading whitespace

my @environment;
foreach my $line (split /\n/, $cdata->{"Environment"}) {
    chomp $line;
    if ($line eq '') {
        next;
    }
    my ($name, $val) = split /=/, $line, 2;
    $val =~ s/^"(.*)"$/$1/;
    push @environment, "$name=$val";
}

# gather all installed build-depends and figure out the version of base-files
my $base_files_version;
my $dpkg_version;
my @inst_build_deps = ();
$inst_build_deps
  = deps_parse($inst_build_deps, reduce_arch => 0, build_dep => 0);
if (!defined $inst_build_deps) {
    die "deps_parse failed\n";
}

foreach my $pkg ($inst_build_deps->get_deps()) {
    if (!$pkg->isa('Dpkg::Deps::Simple')) {
        die "dependency disjunctions are not allowed\n";
    }
    if (not defined($pkg->{package})) {
        die "name undefined\n";
    }
    if (defined($pkg->{relation})) {
        if ($pkg->{relation} ne "=") {
            die "wrong relation";
        }
        if (not defined($pkg->{version})) {
            die "version undefined\n";
        }
    } else {
        die "no version";
    }
    if ($pkg->{package} eq "base-files") {
        if (defined($base_files_version)) {
            die "more than one base-files\n";
        }
        $base_files_version = $pkg->{version};
    } elsif ($pkg->{package} eq "dpkg") {
        if (defined($dpkg_version)) {
            die "more than one dpkg\n";
        }
        $dpkg_version = $pkg->{version};
    }
    push @inst_build_deps,
      {
        name         => $pkg->{package},
        architecture => $pkg->{archqual},
        version      => $pkg->{version} };
}

if (!defined($base_files_version)) {
    die "no base-files\n";
}

if ($builder ne "none") {
    if (!-e $outdir) {
        make_path($outdir);
    }
}

my $build       = '';
my $changesarch = '';
if ($build_archany and $build_archall) {
    $build       = "binary";
    $changesarch = $host_arch;
} elsif ($build_archany and !$build_archall) {
    $build       = "any";
    $changesarch = $host_arch;
} elsif (!$build_archany and $build_archall) {
    $build       = "all";
    $changesarch = 'all';
} else {
    die "nothing to build\n";
}

my @install = ();
foreach my $pkg (@inst_build_deps) {
    my $pkg_name = $pkg->{name};
    my $pkg_ver  = $pkg->{version};
    my $pkg_arch = $pkg->{architecture};
    if (   not defined $pkg_arch
        or $pkg_arch eq "all"
        or $pkg_arch eq $build_arch) {
        push @install, "$pkg_name=$pkg_ver";
    } else {
        push @install, "$pkg_name:$pkg_arch=$pkg_ver";
    }
}

my $debootsnapexe = 'debootsnap';
if ($PROGRAM_NAME eq "scripts/debrebuild.pl" && -x "scripts/debootsnap.py") {
    $debootsnapexe = "scripts/debootsnap.py";
}

# File::Temp has an END block which cleans up the temporary directory
# we created with CLEANUP=>1 but we have to explicitly die() or otherwise
# the interpreter will exit on HUP, INT, PIPE and TERM instead of calling
# the END block
use sigtrap qw(die normal-signals);

# with CLEANUP=>1 this directory will automatically be removed once the
# program exits
my $tmpdir = tempdir('debrebuildXXXXXX', TMPDIR => 1, CLEANUP => 1);

my $tarballpath = '';
my $sourceslist = '';
if (any { $_ eq $builder } ('none', 'dpkg')) {
    open my $fh, '-|', $debootsnapexe, "--buildinfo=$buildinfo",
      '--sources-list-only' // die "cannot exec $debootsnapexe";
    $sourceslist = do { local $/; <$fh> };
    close $fh;
} elsif (any { $_ eq $builder } ('mmdebstrap', 'sbuild', 'sbuild+unshare')) {
    (undef, $tarballpath)
      = tempfile('debrebuild.tar.XXXXXXXXXXXX', OPEN => 0, DIR => $tmpdir);
    0 == system $debootsnapexe, ($cache ? "--cache=$cache" : ()),
      "--buildinfo=$buildinfo", $tarballpath
      or die "$debootsnapexe failed";
} else {
    die "unsupported builder: $builder\n";
}

if ($builder eq "none") {
    print "\n";
    print "Manual installation and build\n";
    print "-----------------------------\n";
    print "\n";
    print
      "The following sources.list contains all the required repositories:\n";
    print "\n";
    print "$sourceslist\n";
    print "\n";
    print "You can manually install the right dependencies like this:\n";
    print "\n";
    print "apt-get install --no-install-recommends";

    # Release files from snapshots.d.o have often expired by the time
    # we fetch them.  Include the option to work around that to assist
    # the user.
    print " -oAcquire::Check-Valid-Until=false";
    foreach my $pkg (@install) {
        print " $pkg";
    }
    print "\n";
    print "\n";
    print "And then build your package:\n";
    print "\n";
    if ($custom_build_path) {
        require Cwd;
        my $custom_build_parent_dir = dirname($custom_build_path);
        my $dsc_path                = Cwd::realpath($dsc_fname)
          // die("Cannot resolve ${dsc_fname}: $!\n");
        print "mkdir -p \"${custom_build_parent_dir}\"\n";
        print qq{dpkg-source -x "${dsc_path}" "${custom_build_path}"\n};
        print "cd \"$custom_build_path\"\n";
    } else {
        print qq{dpkg-source -x "${dsc_fname}"\n};
        print "cd packagedirectory\n";
    }
    print "\n";
    if ($cdata->{"Binary-Only-Changes"}) {
        print(  "Since this is a binNMU, you must put the following "
              . "lines at the top of debian/changelog:\n\n");
        print($cdata->{"Binary-Only-Changes"});
    }
    print "\n";
    print(  "$environment dpkg-buildpackage -uc "
          . "--host-arch=$host_arch --build=$build\n");
} elsif ($builder eq "dpkg") {
    if ("$build_arch\n" ne `dpkg --print-architecture`) {
        die "must be run on $build_arch\n";
    }

    if ($> != 0) {
        die "you must be root for the dpkg builder\n";
    }

    if (-e $custom_build_path) {
        die "$custom_build_path exists -- refusing to overwrite\n";
    }

    my $sources = '/etc/apt/sources.list.d/debrebuild.list';
    if (-e $sources) {
        die "$sources already exists -- refusing to overwrite\n";
    }
    open(FH, '>', $sources) or die "cannot open $sources: $!\n";
    print FH "$sourceslist\n";
    close FH;

    my $config = '/etc/apt/apt.conf.d/23-debrebuild.conf';
    if (-e $config) {
        die "$config already exists -- refusing to overwrite\n";
    }
    open(FH, '>', $config) or die "cannot open $config: $!\n";
    my @common_aptopts = (
        'Acquire::Check-Valid-Until "false";',
        'Acquire::http::Dl-Limit "1000";',
        'Acquire::https::Dl-Limit "1000";',
        'Acquire::Retries "5";',
        'APT::Get::allow-downgrades "true";',
    );
    foreach my $line (@common_aptopts) {
        print FH "$line\n";
    }
    close FH;

    0 == system 'apt-get', 'update' or die "apt-get update failed\n";

    my @cmd
      = ('apt-get', 'install', '--no-install-recommends', '--yes', @install);
    0 == system @cmd or die "apt-get install failed\n";

    0 == system 'apt-get', 'source', '--only-source', '--download-only',
      "$srcpkgname=$srcpkgver"
      or die "apt-get source failed\n";
    unlink $sources or die "failed to unlink $sources\n";
    unlink $config  or die "failed to unlink $config\n";
    make_path(dirname $custom_build_path);
    0 == system 'dpkg-source', '--no-check', '--extract',
      $dsc_fname, $custom_build_path
      or die "dpkg-source failed\n";

    if ($cdata->{"Binary-Only-Changes"}) {
        open my $infh, '<', "$custom_build_path/debian/changelog"
          or die "cannot open debian/changelog for reading: $!\n";
        my $changelogcontent = do { local $/; <$infh> };
        close $infh;
        open my $outfh, '>', "$custom_build_path/debian/changelog"
          or die "cannot open debian/changelog for writing: $!\n";
        my $logentry = $cdata->{"Binary-Only-Changes"};
        # due to storing the binnmu changelog entry in deb822 buildinfo, the
        # first character is an unwanted newline
        $logentry =~ s/^\n//;
        print $outfh $logentry;
        # while the linebreak at the beginning is wrong, there are two missing
        # at the end
        print $outfh "\n\n";
        print $outfh $changelogcontent;
        close $outfh;
    }
    0 == system 'env', "--chdir=$custom_build_path", @environment,
      'dpkg-buildpackage', '-uc', "--host-arch=$host_arch", "--build=$build"
      or die "dpkg-buildpackage failed\n";
    # we are not interested in the unpacked source directory
    0 == system 'rm', '-r', $custom_build_path
      or die "failed to remove $custom_build_path: $?";
    # but instead we want the produced artifacts
    0 == system 'dcmd', 'mv',
      (dirname $custom_build_path)
      . "/${srcpkgname}_${srcpkgbinver}_$changesarch.changes", $outdir
      or die "dcmd failed\n";
} elsif ($builder eq "sbuild" or $builder eq "sbuild+unshare") {
    # we set SBUILD_CONFIG to make sure that the user's ~/.sbuildrc is not
    # being used
    my ($fh, $sbuildrc)
      = tempfile('debrebuild.sbuildrc.XXXXXXXXXXXX', DIR => $tmpdir);
    # there might be no apt inside the chroot and we should have all the build
    # dependencies installed, so make running apt-get and apt-cache a no-op
    print $fh "\$apt_get = '/bin/true';\n";
    print $fh "\$apt_cache = '/bin/true';\n";
    print $fh "\$build_as_root_when_needed = 1;\n";
    close $fh;
    my @cmd = (
        'env', "--chdir=$outdir", @environment, "SBUILD_CONFIG=$sbuildrc",
        'sbuild'
    );
    push @cmd, "--build=$build_arch";
    push @cmd, "--host=$host_arch";

    if ($build_source) {
        push @cmd, '--source';
    } else {
        push @cmd, '--no-source';
    }
    if ($build_archany) {
        push @cmd, '--arch-any';
    } else {
        push @cmd, '--no-arch-any';
    }
    if ($build_archall) {
        push @cmd, '--arch-all';
    } else {
        push @cmd, '--no-arch-all';
    }
    if ($cdata->{"Binary-Only-Changes"}) {
        push @cmd, "--binNMU-changelog=$cdata->{'Binary-Only-Changes'}";
    }
    push @cmd, "--chroot=$tarballpath";
    push @cmd, "--chroot-mode=unshare";
    push @cmd, "--dist=unstable";
    push @cmd, "--no-run-lintian";
    push @cmd, "--no-run-piuparts";
    push @cmd, "--no-run-autopkgtest";
    push @cmd, "--no-apt-update";
    push @cmd, "--no-apt-upgrade";
    push @cmd, "--no-apt-distupgrade";
    # Buildinfo files do not indicate whether fakeroot was installed,
    # so it is not included in the recreated chroot.
    # Since most packages build without issues,
    # this simply forces dpkg-buildpackage to run without fakeroot.
    # the default was switched in 1.22.13 so no longer needed afterwards.
    if ($dpkg_version < Dpkg::Version->new("1.22.13")) {
        push @cmd,
            "--starting-build-commands="
          . 'grep -iq "^Rules-Requires-Root:" "%p/debian/control" || '
          . 'sed -i "1iRules-Requires-Root: no" "%p/debian/control"';
    }
    # without --verbose, the log will be suppressed by default if sbuild is
    # not run on an interactive tty, so we make sure the behaviour is always
    # the same independent how debrebuild is run
    push @cmd, "--verbose";
    # since sbuild will always output to stdout, thanks to --verbose, we
    # do not need to put the log file to disk anymore. Those interested in the
    # log, can just capture stdout of debrebuild
    push @cmd, "--nolog";
    # disable the explainer
    push @cmd, "--bd-uninstallable-explainer=";

    if ($custom_build_path) {
        my @dirs       = File::Spec->splitdir($custom_build_path);
        my $build_path = File::Spec->catdir(@dirs[0 .. $#dirs - 1]);
        push @cmd, "--build-path=$build_path";
        push @cmd, "--dsc-dir=$dirs[-1]";
    }
    push @cmd, (File::Spec->rel2abs($dsc_fname));
    print((join " ", @cmd) . "\n");
    0 == system @cmd or die "sbuild failed\n";

    unlink $sbuildrc;
} elsif ($builder eq "mmdebstrap") {

    my @binnmucmds = ();
    if ($cdata->{"Binary-Only-Changes"}) {
        my $logentry = $cdata->{"Binary-Only-Changes"};
     # due to storing the binnmu changelog entry in deb822 buildinfo, the first
     # character is an unwanted newline
        $logentry =~ s/^\n//;
      # while the linebreak at the beginning is wrong, there are two missing at
      # the end
        $logentry .= "\n\n";
        push @binnmucmds,
            '{ printf "%s" '
          . (String::ShellQuote::shell_quote $logentry)
          . "; cat debian/changelog; } > debian/changelog.debrebuild",
          "mv debian/changelog.debrebuild debian/changelog";
    }

    my @cmd = (
        'env', '-i',
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin',
        'mmdebstrap',
        "--arch=$build_arch",
        "--variant=custom",
        '--skip=setup',
        '--skip=update',
        '--skip=cleanup',
        '--skip=tar-in/mknod',
        "--setup-hook=tar-in "
          . (String::ShellQuote::shell_quote $tarballpath) . ' /',
        '--setup-hook=rm "$1"/etc/apt/sources.list',
        (
                "--customize-hook=dcmd cp "
              . (String::ShellQuote::shell_quote $dsc_fname)
              . " \"\$1\""
        ),
        '--customize-hook=chroot "$1" sh -c "'
          . (
            join ' && ',
            "mkdir -p "
              . (String::ShellQuote::shell_quote(dirname $custom_build_path)),
            "dpkg-source --no-check -x /"
              . $srcpkg->get_basename(1) . '.dsc '
              . (String::ShellQuote::shell_quote $custom_build_path),
            'cd ' . (String::ShellQuote::shell_quote $custom_build_path),
            @binnmucmds,
"env $environment dpkg-buildpackage -uc -a $host_arch --build=$build",
            'cd /',
            'rm -r ' . (String::ShellQuote::shell_quote $custom_build_path))
          . '"',
        '--customize-hook=sync-out '
          . (dirname $custom_build_path)
          . " $outdir",
        '',
        '/dev/null',
    );
    print((join ' ', @cmd) . "\n");

    0 == system @cmd or die "mmdebstrap failed\n";
} else {
    die "unsupported builder: $builder\n";
}

# test if all checksums in the buildinfo file check out
if ($builder ne "none") {
    print "build artifacts stored in $outdir\n";

    my $checksums = Dpkg::Checksums->new();
    $checksums->add_from_control($cdata);
    # remove the .dsc as we only did the binaries
    #  - the .dsc cannot be reproduced anyways because we cannot reproduce its
    #    signature
    #  - binNMUs can only be done with --build=any
    foreach my $file ($checksums->get_files()) {
        if ($file !~ /\.dsc$/) {
            next;
        }
        $checksums->remove_file($file);
    }

    my $new_cdata
      = Dpkg::Control->new(type => CTRL_FILE_BUILDINFO, allow_pgp => 1);
    $new_cdata->load($new_buildinfo);
    my $new_checksums = Dpkg::Checksums->new();
    $new_checksums->add_from_control($new_cdata);

    my @files     = $checksums->get_files();
    my @new_files = $new_checksums->get_files();

    if (scalar @files != scalar @new_files) {
        print("old buildinfo:\n" . (join "\n", @files) . "\n");
        print("new buildinfo:\n" . (join "\n", @new_files) . "\n");
        die "new buildinfo contains a different number of files\n";
    }

    for (my $i = 0 ; $i <= $#files ; $i++) {
        if ($files[$i] ne $new_files[$i]) {
            die "different checksum files at position $i\n";
        }
        if ($files[$i] =~ /\.dsc$/) {
            print("skipping $files[$i]\n");
            next;
        }
        print("checking $files[$i]: ");
        if ($checksums->get_size($files[$i])
            != $new_checksums->get_size($files[$i])) {
            die "size differs for $files[$i]\n";
        } else {
            print("size... ");
        }
        my $chksum     = $checksums->get_checksum($files[$i], undef);
        my $new_chksum = $new_checksums->get_checksum($new_files[$i], undef);
        if (scalar keys %{$chksum} != scalar keys %{$new_chksum}) {
            die "different algos for $files[$i]\n";
        }
        foreach my $algo (keys %{$chksum}) {
            if (!exists $new_chksum->{$algo}) {
                die "$algo is not used in both buildinfo files\n";
            }
            if ($chksum->{$algo} ne $new_chksum->{$algo}) {
                die "value of $algo differs for $files[$i]\n";
            }
            print("$algo... ");
        }
        print("all OK\n");
    }
}
