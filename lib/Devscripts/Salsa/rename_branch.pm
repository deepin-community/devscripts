package Devscripts::Salsa::rename_branch;

use strict;
use Devscripts::Output;
use Moo::Role;

with "Devscripts::Salsa::Repo";

our $prompt = 1;

sub rename_branch {
    my ($self, @reponames) = @_;
    my $res   = 0;
    my @repos = $self->get_repo($prompt, @reponames);
    return @repos unless (ref $repos[0]);    # get_repo returns 1 when fails
    foreach (@repos) {
        my $id  = $_->[0];
        my $str = $_->[1];
        if (!$id) {
            ds_warn "Branch rename has failed for $str (missing ID)\n";
            return 1;
        }
        ds_verbose "Configuring $str";
        my $project = $self->api->project($id);
        eval {
            $self->api->create_branch(
                $id,
                {
                    ref    => $self->config->source_branch,
                    branch => $self->config->dest_branch,
                });
            $self->api->delete_branch($id, $self->config->source_branch);
        };
        if ($@) {
            ds_warn "Branch rename has failed for $str\n";
            ds_verbose $@;
            unless ($self->config->no_fail) {
                ds_verbose "Use --no-fail to continue";
                return 1;
            }
            next;
        }
    }
    return $res;
}

1;
