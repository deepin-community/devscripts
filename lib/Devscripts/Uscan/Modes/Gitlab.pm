package Devscripts::Uscan::Modes::Gitlab;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::Modes::_xtp;
use Moo::Role;
use LWP::UserAgent;
use URI;
use URI::Escape;

BEGIN {
    eval 'use JSON';
    if ($@) {
        die "You must install libjson-perl to use Gitlab mode";
    }
}

sub gitlab_search {
    my ($self) = @_;
    my $uri = $self->{parse_result}->{base};
    $uri =~ s#/+$##;
    uscan_verbose "Searching versions of $uri";
    unless ($uri =~ m#^https?://.*?/.*?/#) {
        uscan_die "Bad uri $uri";
        return;
    }
    $uri = URI->new($uri);
    my $path = $uri->path;
    $path =~ s#^/+##;
    my $ua = LWP::UserAgent->new;
    $ua->env_proxy;

    # Get project ID
    my $baseUrl = $uri->scheme . '://' . $uri->host . '/api/v4';
    my $query   = "$baseUrl/projects/" . uri_escape($path);
    my $resp    = $ua->get($query);
    unless ($resp->is_success) {
        uscan_die 'Bad response from Gitlab server: '
          . $resp->status_line
          . " ($query)";
        return;
    }
    my $projectId = eval { from_json($resp->decoded_content)->{id} };
    unless ($projectId and !$@) {
        uscan_die "Unable to get project_id from $query";
        return;
    }
    uscan_verbose "Gitlab project_id is $projectId";

    # Get project tags
    $resp = $ua->get("$baseUrl/projects/$projectId/repository/tags");
    my $tmp = eval { from_json($resp->decoded_content) };
    if ($@) {
        uscan_die "Bad response from Gitlab server: $@";
        return;
    }

    # Get versions that match
    my @tags = map {
        (         $_->{name}
              and $_->{name} =~ /^$self->{parse_result}->{filepattern}$/
              and (!$self->releaseonly or $_->{release}))
          ? [
            $_->{name},
"$baseUrl/projects/$projectId/repository/archive.tar.gz?sha=$_->{name}"
          ]
          : ()
    } @$tmp;

    my @files;
    for (my $i = 0 ; $i < @tags ; $i++) {
        my ($version, $file) = @{ $tags[$i] };
        my $mangled_version = $version;
        if (
            mangle(
                $self->watchfile,            'uversionmangle:',
                \@{ $self->uversionmangle }, \$mangled_version
            )
        ) {
            return undef;
        }
        my $match = '';
        if (defined $self->shared->{download_version}) {
            if ($version eq $self->shared->{download_version}) {
                $match = "matched with the download version";
            }
        }
        my $priority = $mangled_version . '-' . get_priority($file);
        push @files, [$priority, $mangled_version, $file, $match, $version];
    }
    return sortAndMangle($self, @files);
}

sub gitlab_upstream_url {
    my ($self) = @_;
    return $self->search_result->{newfile};
}

*gitlab_newfile_base = \&Devscripts::Uscan::Modes::_xtp::_xtp_newfile_base;

sub gitlab_clean { 0 }

1;
