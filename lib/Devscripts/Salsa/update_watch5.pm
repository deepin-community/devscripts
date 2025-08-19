package Devscripts::Salsa::update_watch5;

use strict;
use Devscripts::Output;
use Devscripts::Uscan::Version4;
use Dpkg::IPC;
use MIME::Base64;
use Moo::Role;
use File::Temp 'tempdir';

with "Devscripts::Salsa::Repo";

sub update_watch5 {
    my ($self, @reponames) = @_;
    my $ret = 0;
    my @fail;
    unless (@reponames or $self->config->all or $self->config->all_archived) {
        ds_warn "Usage $0 check_repo <--all|--all-archived|names>";
        return 1;
    }
    if (@reponames and $self->config->all) {
        ds_warn "--all with a reponame makes no sense";
        return 1;
    }
    if (@reponames and $self->config->all_archived) {
        ds_warn "--all-archived with a reponame makes no sense";
        return 1;
    }
    my @repos = $self->get_repo(0, @reponames);
    return @repos unless (ref $repos[0]);
    my $wdir = tempdir(CLEANUP => 1);
    my $i    = 0;
    foreach my $repo (@repos) {
        if ($ret and !$self->config->no_fail) {
            return $ret;
        }
        my ($id, $name) = @$repo;
        unless ($id) {
            ds_debug $@;
            ds_warn "Project $name not found";
            $ret++;
            next;
        }
        my $project = eval { $self->api->project($id) };
        unless ($project) {
            ds_debug $@;
            ds_warn "Project $name not found";
            $ret++;
            next;
        }
        ds_debug "Get debian/watch from $name ($id)";
        my $wbranch
          = $self->config->debian_branch || $project->{default_branch};
        my $res = $self->api->file($id, 'debian/watch', { ref => $wbranch });

        unless ($res) {
            ds_warn
              "Project $name has no debian/watch file in branch $wbranch";
            $ret++;
            next;
        }
        my $content = decode_base64($res->{content});
        unless ($content) {
            ds_warn "Empty debian/watch file in branch $wbranch";
            $ret++;
            next;
        }
        if ($content =~ /Version:\s+5/s) {
            ds_warn "Project $name already updated";
            next;
        }
        $i++;
        open my $fh, '>', "$wdir/$i" or die $!;
        print $fh $content;
        $fh->close;
        my $watch5 = Devscripts::Uscan::Version4->new("$wdir/$i");
        unless ($watch5) {
            ds_warn "Unable to transform debian/watch from $name ($id)";
            $ret++;
            next;
        } else {
            local $/ = undef;
            $content = <$watch5>;
        }
        $watch5->close;
        $content =~ s/(\r?\n){2}$/$1/s;

        $res = $self->api->edit_file(
            $id,
            'debian/watch',
            {
                branch         => $wbranch,
                commit_message =>
                  'Update debian/watch to version 5 using salsa update_watch5',
                content => $content,
            });
    }
    return $ret;
}

1;
