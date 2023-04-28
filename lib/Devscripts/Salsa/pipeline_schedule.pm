# Create a pipeline schedule using parameters
package Devscripts::Salsa::pipeline_schedule;

use strict;
use Devscripts::Output;
use Moo::Role;

# For --all
with "Devscripts::Salsa::Repo";

sub pipeline_schedule {
    my ($self, @repos) = @_;
    my $ret    = 0;
    my $desc   = $self->config->schedule_desc;
    my $ref    = $self->config->schedule_ref;
    my $cron   = $self->config->schedule_cron;
    my $tz     = $self->config->schedule_tz;
    my $active = $self->config->schedule_enable;
    $active
      = ($self->config->schedule_disable)
      ? "0"
      : $active;
    my $run    = $self->config->schedule_run;
    my $delete = $self->config->schedule_delete;

    unless (@repos or $self->config->all) {
        ds_warn "Usage $0 pipeline <project|--all>";
        return 1;
    }
    if (@repos and $self->config->all) {
        ds_warn "--all with a project (@repos) makes no sense";
        return 1;
    }

    unless ($desc) {
        ds_warn "--schedule-desc / SALSA_SCHEDULE_DESC is missing";
        ds_warn "Are you looking for: $0 pipelines <project|--all>";
        return 1;
    }

    # If --all is asked, launch all projects
    @repos = map { $_->[1] } $self->get_repo(0, @repos) unless (@repos);

    foreach my $repo (sort @repos) {
        my $id = $self->project2id($repo);
        unless ($id) {
#ds_warn "Project $repo not found";   # $self->project2id($repo) shows this error
            $ret++;
            return 1 unless $self->config->no_fail;
        } else {
            my @pipe_id = ();
            $desc =~ s/%p/$repo/g;
            my $options = {};
            $options->{ref}           = $ref    if defined $ref;
            $options->{cron}          = $cron   if defined $cron;
            $options->{cron_timezone} = $tz     if defined $tz;
            $options->{active}        = $active if defined $active;

# REF: https://docs.gitlab.com/ee/api/pipeline_schedules.html#get-all-pipeline-schedules
# $self->api->pipeline_schedules($id)
            my $pipelines
              = $self->api->paginator('pipeline_schedules', $id)->all();
            ds_verbose "No pipelines scheduled for $repo" unless @$pipelines;

            foreach (@$pipelines) {
                push @pipe_id, $_->{id}
                  if ($_->{description} eq $desc);
            }

            ds_warn "More than 1 scheduled pipeline matches: $desc ("
              . ++$#pipe_id . ")"
              if ($pipe_id[1]);

            if (!@pipe_id) {
                ds_warn "--schedule-ref / SALSA_SCHEDULE_REF is required"
                  unless ($ref);
                ds_warn "--schedule-cron / SALSA_SCHEDULE_CRON is required"
                  unless ($cron);
                return 1
                  unless ($ref && $cron);

                $options->{description} = $desc if defined $desc;

                ds_verbose "No scheduled pipelines matching: $desc. Creating!";
                my $schedule
                  = $self->api->create_pipeline_schedule($id, $options);

                @pipe_id = $schedule->{id};
            } elsif (keys %$options) {
                ds_verbose "Editing scheduled pipelines matching: $desc";
                foreach (@pipe_id) {
                    next if !$_;

                    my $schedule
                      = $self->api->edit_pipeline_schedule($id, $_, $options);
                }
            }

            if ($run) {
                ds_verbose "Running scheduled pipelines matching: $desc";

                foreach (@pipe_id) {
                    next if !$_;

                    my $schedule = $self->api->run_pipeline_schedule($id, $_);
                }
            }

            if ($delete) {
                ds_verbose "Deleting scheduled pipelines matching: $desc";

                foreach (@pipe_id) {
                    next if !$_;

                    my $schedule
                      = $self->api->delete_pipeline_schedule($id, $_);
                }
            }
        }
    }
    return $ret;
}

1;
