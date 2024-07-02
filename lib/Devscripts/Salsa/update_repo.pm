# Updates projects
package Devscripts::Salsa::update_repo;    # update_projects

use strict;
use Devscripts::Output;
use GitLab::API::v4::Constants qw(:all);
use Moo::Role;

with "Devscripts::Salsa::Repo";

our $prompt = 1;

sub update_repo {
    my ($self, @reponames) = @_;
    if ($ds_yes < 0 and $self->config->command eq 'update_repo') {
        ds_warn
"update_projects can't be launched when --info is set, use update_safe";
        return 1;
    }
    unless (@reponames or $self->config->all or $self->config->all_archived) {
        ds_warn "Usage $0 update_projects <--all|--all-archived|names>";
        return 1;
    }
    if (@reponames and $self->config->all) {
        ds_warn "--all with a project name makes no sense";
        return 1;
    }
    if (@reponames and $self->config->all_archived) {
        ds_warn "--all-archived with a project name makes no sense";
        return 1;
    }
    return $self->_update_repo(@reponames);
}

sub _update_repo {
    my ($self, @reponames) = @_;
    my $res = 0;
    # Common options
    my $configparams = {};
    # visibility can be modified only by group owners
    $configparams->{visibility} = 'public'
      if $self->access_level >= $GITLAB_ACCESS_LEVEL_OWNER;
    # get project list using Devscripts::Salsa::Repo
    my @repos = $self->get_repo($prompt, @reponames);
    return @repos unless (ref $repos[0]);    # get_repo returns 1 when fails
    foreach my $repo (@repos) {
        my $id  = $repo->[0];
        my $str = $repo->[1];
        ds_verbose "Configuring $str";
        eval {
            # apply new parameters
            $self->api->edit_project($id,
                { %$configparams, $self->desc($str) });
            # Set project avatar
            my @avatar_file = $self->desc_multipart($str);
            $self->api->edit_project_multipart($id, {@avatar_file})
              if (@avatar_file and $self->config->avatar_path);
            # add hooks if needed
            $str =~ s#^.*/##;
            $self->add_hooks($id, $str);
        };
        if ($@) {
            ds_warn "update_projects has failed for $str\n";
            ds_verbose $@;
            $res++;
            unless ($self->config->no_fail) {
                ds_verbose "Use --no-fail to continue";
                return 1;
            }
            next;
        } elsif ($self->config->rename_head) {
            # 1 - creates new branch if --rename-head
            my $project = $self->api->project($id);
            if ($project->{default_branch} ne $self->config->dest_branch) {
                eval {
                    $self->api->create_branch(
                        $id,
                        {
                            ref    => $self->config->source_branch,
                            branch => $self->config->dest_branch,
                        });
                };
                if ($@) {
                    ds_debug $@ if ($@);
                    $project = undef;
                }

                eval {
                    $self->api->edit_project($id,
                        { default_branch => $self->config->dest_branch });
                    # delete old branch only if "create_branch" succeed
                    if ($project) {
                        $self->api->delete_branch($id,
                            $self->config->source_branch);
                    }
                };
                if ($@) {
                    ds_warn "Branch rename has failed for $str\n";
                    ds_verbose $@;
                    $res++;
                    unless ($self->config->no_fail) {
                        ds_verbose "Use --no-fail to continue";
                        return 1;
                    }
                    next;
                }
            } else {
                ds_verbose "Head already renamed for $str";
            }
        }
        ds_verbose "Project $str updated";
    }
    return $res;
}

sub access_level {
    my ($self) = @_;
    my $user_id = $self->api->current_user()->{id};
    if ($self->group_id) {
        my $tmp = $self->api->all_group_members($self->group_id,
            { user_ids => $user_id });
        unless ($tmp) {
            my $members
              = $self->api->paginator('all_group_members', $self->group_id,
                { query => $user_id });
            while ($_ = $members->next) {
                return $_->{access_level} if ($_->{id} eq $user_id);
            }
            ds_warn "You're not member of this group";
            return 0;
        }
        return $tmp->[0]->{access_level};
    }
    return $GITLAB_ACCESS_LEVEL_OWNER;
}

1;
