package Devscripts::Uscan::Modes::Metacpan;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::Modes::_xtp;
use Moo::Role;

BEGIN {
    eval 'use MetaCPAN::Client';
    if ($@) {
        die "You must install libmetacpan-client-perl";
    }
}

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
    return sortAndMangle($self, @files);
}

sub metacpan_upstream_url {
    my ($self) = @_;
    return $self->search_result->{newfile};
}

*metacpan_newfile_base = \&Devscripts::Uscan::Modes::_xtp::_xtp_newfile_base;

sub metacpan_clean { 0 }

1;
