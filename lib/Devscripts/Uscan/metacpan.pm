package Devscripts::Uscan::metacpan;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::_xtp;
use Moo::Role;
use MetaCPAN::Client;

sub metacpan_search {
    my ($self) = @_;
    uscan_verbose "Searching versions of $self->{parse_result}->{base}";
    my $mcpan    = MetaCPAN::Client->new;
    my $releases = $mcpan->release({
            all => [{
                    distribution => $self->{parse_result}->{base} }
            ],
            fields => [qw(version download_url)] });

    my (@files);
    while (my $release = $releases->next) {
        my $mangled_version = $release->version;
        my $file            = $release->download_url;
        if (
            mangle(
                $self->watchfile,            'uversionmangle:',
                \@{ $self->uversionmangle }, \$mangled_version
            )
        ) {
            return undef;
        }
        my $match = '';
        if (defined $self->shared->{download_version}
            and not $self->versionmode eq 'ignore') {
            if ($mangled_version eq $self->shared->{download_version}) {
                $match = "matched with the download version";
            }
        }
        my $priority = $mangled_version . '-' . get_priority($file);
        push @files,
          [$priority, $mangled_version, $file, $match, $release->version];
    }
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
    if (defined $self->shared->{download_version}) {

        # extract ones which has $match in the above loop defined
        my @vfiles = grep { $$_[3] } @files;
        if (@vfiles) {
            (undef, $mangled_newversion, $newfile, undef, $newversion)
              = @{ $vfiles[0] };
        } else {
            uscan_warn
"In $self->{watchfile} no matching files for version $self->{shared}->{download_version}"
              . " in watch line";
            return undef;
        }
    } else {
        if (@files) {
            (undef, $mangled_newversion, $newfile, undef, $newversion)
              = @{ $files[0] };
        } else {
            uscan_warn
              "In $self->{watchfile} no matching files for watch source\n  "
              . $self->{watchSource}->{source};
            return undef;
        }
    }
    return ($mangled_newversion, $newversion, $newfile);
}

sub metacpan_upstream_url {
    my ($self) = @_;
    return $self->search_result->{newfile};
}

*metacpan_newfile_base = \&Devscripts::Uscan::_xtp::_xtp_newfile_base;

sub metacpan_clean { 0 }

1;
