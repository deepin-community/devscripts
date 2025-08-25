# Common sub shared between git and svn
package Devscripts::Uscan::Modes::_vcs;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Exporter 'import';
use File::Basename;

our @EXPORT = ('get_refs');

our $progname = basename($0);

sub _vcs_newfile_base {
    my ($self) = @_;
    # Compression may optionally be deferred to mk-origtargz
    my $newfile_base = "$self->{pkg}-$self->{search_result}->{newversion}.tar";
    if (!$self->config->{vcs_export_uncompressed}) {
        $newfile_base .= '.' . get_suffix($self->compression);
    }
    if (@{ $self->filenamemangle }) {
        my $cmp = $newfile_base;
        uscan_verbose "Matching target for filenamemangle: $newfile_base";
        if (
            mangle(
                $self->watchfile,            'filenamemangle:',
                \@{ $self->filenamemangle }, \$newfile_base
            )
        ) {
            $self->status(1);
            return undef;
        }
        if ($cmp eq $newfile_base) {
            uscan_die "filenamemangle failed for $cmp";
        }
        if ($self->versionless) {
            # set version from filenamemangling result
            $newfile_base
              =~ m/^.+?[-_]?(\d[\-+\.:\~\da-zA-Z]*)(?:\.tar(\..*)?)$/i;
            $self->search_result->{newversion}
              = $self->search_result->{mangled_newversion} = $1;
            unless ($self->search_result->{mangled_newversion}) {
                uscan_warn
"Fix filenamemangle to produce a filename with the correct version";
                $self->status(1);
                return undef;
            }
            uscan_verbose
"Newest upstream tarball version from the filenamemangled filename: $self->{search_result}->{newversion}";
        }
    }
    return $newfile_base;
}

sub get_refs {
    my ($self, $command, $ref_pattern, $package) = @_;
    my @command = @$command;
    my ($newfile, $newversion, $mangled_newversion);
    {
        local $, = ' ';
        uscan_verbose "Execute: @command";
    }
    open(REFS, "-|", @command)
      || uscan_die "$progname: you must have the $package package installed";
    my @refs;
    my $ref;
    my $version;
    my $mangled_version;
    while (<REFS>) {
        chomp;
        uscan_debug "$_";
        if ($_ =~ $ref_pattern) {
            $ref = $1;
            foreach my $_pattern (@{ $self->patterns }) {
                $mangled_version = $version = join(".",
                    map { $_ if defined($_) } $ref =~ m&^$_pattern$&);
                if (
                    mangle(
                        $self->watchfile,            'uversionmangle:',
                        \@{ $self->uversionmangle }, \$mangled_version
                    )
                ) {
                    return undef;
                }
                push @refs, [$mangled_version, $version, $ref];
            }
        }
    }
    if (@refs) {
        @refs = Devscripts::Versort::upstream_versort(@refs);
        my $msg = "Found the following matching refs:\n";
        foreach my $ref (@refs) {
            $msg .= "     $$ref[2] ($$ref[0])\n";
        }
        uscan_verbose "$msg";
        if ($self->shared->{download_version}
            and not $self->versionmode eq 'ignore') {

# extract ones which has $version in the above loop matched with $download_version
            my @vrefs
              = grep { $$_[1] eq $self->shared->{download_version} } @refs;
            if (@vrefs) {
                ($mangled_newversion, $newversion, $newfile) = @{ $vrefs[0] };
            } else {
                uscan_warn
                  "$progname warning: In $self->{watchfile} no matching"
                  . " refs for version "
                  . $self->shared->{download_version}
                  . " in watch line\n  "
                  . $self->{line};
                return undef;
            }

        } else {
            ($mangled_newversion, $newversion, $newfile) = @{ $refs[0] };
        }
    } else {
        uscan_warn "$progname warning: In $self->{watchfile},\n"
          . " no matching refs for watch line\n"
          . " $self->{line}";
        return undef;
    }
    return ($mangled_newversion, $newversion, $newfile);
}

1;
