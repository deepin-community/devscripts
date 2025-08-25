# Common sub shared between http and ftp
package Devscripts::Uscan::Modes::_xtp;

use strict;
use File::Basename;
use Exporter 'import';
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;

our @EXPORT = qw(partial_version sortAndMangle);

sub _xtp_newfile_base {
    my ($self) = @_;
    my $newfile_base;
    if (@{ $self->filenamemangle }) {

        # HTTP or FTP site (with filenamemangle)
        if ($self->versionless) {
            $newfile_base = $self->upstream_url;
        } else {
            $newfile_base = $self->search_result->{newfile};
        }
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
        if ($newfile_base =~ m/^(?:https?|ftp):/) {
            $newfile_base = basename($newfile_base);
        }
        if ($cmp eq $newfile_base) {
            uscan_die "filenamemangle failed for $cmp";
        }
        unless ($self->search_result->{mangled_newversion}) {

            # uversionmangled version is '', make best effort to set it
            $newfile_base
              =~ m/^.+?[-_]?(\d[\-+\.:\~\da-zA-Z]*)(?:\.tar\.(gz|bz2|xz|zstd?)|\.zip)$/i;
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
    } else {
        # HTTP or FTP site (without filenamemangle)
        $newfile_base = basename($self->search_result->{newfile});
        if ($self->mode eq 'http') {

            # Remove HTTP header trash
            $newfile_base =~ s/[\?#].*$//;    # PiPy
                # just in case this leaves us with nothing
            if ($newfile_base eq '') {
                uscan_warn
"No good upstream filename found after removing tailing ?... and #....\n   Use filenamemangle to fix this.";
                $self->status(1);
                return undef;
            }
        }
    }
    return $newfile_base;
}

sub partial_version {
    my ($download_version) = @_;
    my ($d1, $d2, $d3);
    if (defined $download_version) {
        uscan_verbose "download version requested: $download_version";
        if ($download_version
            =~ m/^([-~\+\w]+)(\.[-~\+\w]+)?(\.[-~\+\w]+)?(\.[-~\+\w]+)?$/) {
            $d1 = "$1"     if defined $1;
            $d2 = "$1$2"   if defined $2;
            $d3 = "$1$2$3" if defined $3;
        }
    }
    return ($d1, $d2, $d3);
}

sub sortAndMangle {
    my ($watchSource, @files) = @_;
    if (@files) {
        @files = Devscripts::Versort::versort(@files);
        my $msg
          = "Found the following matching files on the web page (newest first):\n";
        foreach my $file (@files) {
            $msg .= "   $$file[2] ($$file[1]) index=$$file[0] $$file[3]\n";
        }
        uscan_verbose $msg;
    }
    my ($mangled_newversion, $newversion, $newfile);
    if (defined $watchSource->shared->{download_version}
        and not $watchSource->versionmode eq 'ignore') {

        # extract ones which has $match in the above loop defined
        my @vfiles = grep { $$_[3] } @files;
        if (@vfiles) {
            (undef, $mangled_newversion, $newfile, undef, $newversion)
              = @{ $vfiles[0] };
        } else {
            uscan_warn
              "In $watchSource->{watchfile} no matching files for version "
              . "$watchSource->{shared}->{download_version}"
              . " in watch line";
            return undef;
        }
    } else {
        if (@files) {
            (undef, $mangled_newversion, $newfile, undef, $newversion)
              = @{ $files[0] };
        } else {
            uscan_warn
"In $watchSource->{watchfile} no matching files for watch source\n  "
              . $watchSource->{watchSource}->{source};
            return undef;
        }
    }
    return ($mangled_newversion, $newversion, $newfile);
}

1;
