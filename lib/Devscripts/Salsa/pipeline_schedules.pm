# Lists pipeline schedules of a project
package Devscripts::Salsa::pipeline_schedules;

use strict;
use Devscripts::Output;
use Moo::Role;

# For --all
with "Devscripts::Salsa::Repo";

sub pipeline_schedules {
    my ($self, @repo) = @_;
    my $ret = 0;

    unless (@repo or $self->config->all) {
        ds_warn "Usage $0 pipelines <project|--all>";
        return 1;
    }
    if (@repo and $self->config->all) {
        ds_warn "--all with a project (@repo) makes no sense";
        return 1;
    }

    # If --all is asked, launch all projects
    @repo = map { $_->[1] } $self->get_repo(0, @repo) unless (@repo);

    foreach my $p (sort @repo) {
        my $id    = $self->project2id($p);
        my $count = 0;
        unless ($id) {
    #ds_warn "Project $p not found";   # $self->project2id($p) shows this error
            $ret++;
            return 1 unless $self->config->no_fail;
        } else {
            my $projects = $self->api->project($id);
            if ($projects->{jobs_enabled} == 0) {
                print "$p has disabled CI/CD\n";
                next;
            }

            my $pipelines
              = $self->api->paginator('pipeline_schedules', $id)->all();

            print "$p\n" if @$pipelines;

            foreach (@$pipelines) {
                my $status = $_->{active} ? 'Enabled' : 'Disabled';
                print <<END;
\tID         : $_->{id}
\tDescription: $_->{description}
\tStatus     : $status
\tRef        : $_->{ref}
\tCron       : $_->{cron}
\tTimezone   : $_->{cron_timezone}
\tCreated    : $_->{created_at}
\tUpdated    : $_->{updated_at}
\tNext run   : $_->{next_run_at}
\tOwner      : $_->{owner}->{username}

END
            }
        }
        unless ($count) {
            next;
        }
    }
    return $ret;
}

1;
