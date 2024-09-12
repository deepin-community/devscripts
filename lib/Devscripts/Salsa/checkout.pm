# Clones or updates a project's repository using gbp
# TODO: git-dpm ?
package Devscripts::Salsa::checkout;

use strict;
use Devscripts::Output;
use Devscripts::Utils;
use Dpkg::IPC;
use Moo::Role;

with "Devscripts::Salsa::Repo";

sub checkout {
    my ($self, @repos) = @_;
    unless (@repos or $self->config->all or $self->config->all_archived) {
        ds_warn "Usage $0 checkout <--all|--all-archived|names>";
        return 1;
    }
    if (@repos and $self->config->all) {
        ds_warn "--all with a project name makes no sense";
        return 1;
    }
    if (@repos and $self->config->all_archived) {
        ds_warn "--all-archived with a project name makes no sense";
        return 1;
    }
    # If --all is asked, launch all projects
    @repos = map { $_->[1] } $self->get_repo(0, @repos) unless (@repos);
    my $cdir = `pwd`;
    chomp $cdir;
    my $res = 0;
    foreach (@repos) {
        my $path = $self->project2path($_);
        s#.*/##;
        if (-d $_) {
            chdir $_;
            ds_verbose "Updating existing checkout in $_";
            spawn(
                exec       => ['gbp', 'pull', '--pristine-tar'],
                wait_child => 1,
                nocheck    => 1,
            );
            if ($?) {
                $res++;
                if ($self->config->no_fail) {
                    print STDERR "gbp pull fails in $_\n";
                } else {
                    ds_warn "gbp pull failed in $_\n";
                    ds_verbose "Use --no-fail to continue";
                    return 1;
                }
            }
            chdir $cdir;
        } else {
            spawn(
                exec => [
                    'gbp',   'clone',
                    '--all', $self->config->git_server_url . $path . ".git"
                ],
                wait_child => 1,
                nocheck    => 1,
            );
            if ($?) {
                $res++;
                if ($self->config->no_fail) {
                    print STDERR "gbp clone fails in $_\n";
                } else {
                    ds_warn "gbp clone failed for $_\n";
                    ds_verbose "Use --no-fail to continue";
                    return 1;
                }
            }
            ds_warn "$_ ready in $_/";
        }
    }
    return $res;
}

1;
