package Devscripts::Salsa;

=head1 NAME

Devscripts::Salsa - salsa(1) base object

=head1 SYNOPSIS

  use Devscripts::Salsa;
  exit Devscripts::Salsa->new->run

=head1 DESCRIPTION

Devscripts::Salsa provides salsa(1) command launcher and some common utilities
methods.

=cut

use strict;

use Devscripts::Output;
use Devscripts::Salsa::Config;

BEGIN {
    eval "use GitLab::API::v4;use GitLab::API::v4::Constants qw(:all)";
    if ($@) {
        print STDERR "You must install GitLab::API::v4\n";
        exit 1;
    }
}
use Moo;
use File::Basename;
use File::Path qw(make_path);

# Command aliases
use constant cmd_aliases => {
    # Alias => Filename -> ./lib/Devscripts/Salsa/*.pm
    # Preferred terminology
    check_projects  => 'check_repo',
    create_project  => 'create_repo',
    delete_project  => 'del_repo',
    delete_user     => 'del_user',
    list_projects   => 'list_repos',
    list_users      => 'group',
    search_groups   => 'search_group',
    search_projects => 'search_project',
    search_users    => 'search_user',
    update_projects => 'update_repo',

    # Catch possible typo (As able to-do multiple items at once)
    list_user      => 'group',
    check_project  => 'check_repo',
    list_project   => 'list_repos',
    update_project => 'update_repo',

    # Abbreviation
    co        => 'checkout',
    ls        => 'list_repos',
    mr        => 'merge_request',
    mrs       => 'merge_requests',
    schedule  => 'pipeline_schedule',
    schedules => 'pipeline_schedules',

    # Legacy
    search      => 'search_project',
    search_repo => 'search_project',
};

=head1 ACCESSORS

=over

=item B<config> : Devscripts::Salsa::Config object (parsed)

=cut

has config => (
    is      => 'rw',
    default => sub { Devscripts::Salsa::Config->new->parse },
);

=item B<cache> : Devscripts::JSONCache object

=cut

# File cache to avoid polling GitLab too much
# (used to store ids, paths and names)
has _cache => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        return {} unless ($_[0]->config->cache_file);
        my %h;
        eval {
            my ($cache_file, $cache_dir) = fileparse $_[0]->config->cache_file;
            if (!-d $cache_dir) {
                make_path $cache_dir;
            }
            require Devscripts::JSONCache;
            tie %h, 'Devscripts::JSONCache', $_[0]->config->cache_file;
            ds_debug "Cache opened";
        };
        if ($@) {
            ds_verbose "Unable to create cache object: $@";
            return {};
        }
        return \%h;
    },
);
has cache => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        $_[0]->_cache->{ $_[0]->config->api_url } //= {};
        return $_[0]->_cache->{ $_[0]->config->api_url };
    },
);

# In memory cache (used to avoid querying the project id twice when using
# update_safe
has projectCache => (
    is      => 'rw',
    default => sub { {} },
);

=item B<api>: GitLab::API::v4 object

=cut

has api => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $r = GitLab::API::v4->new(
            url => $_[0]->config->api_url,
            (
                $_[0]->config->private_token
                ? (private_token => $_[0]->config->private_token)
                : ()
            ),
        );
        $r or ds_die "Unable to create GitLab::API::v4 object";
        return $r;
    },
);

=item User or group in use

=over

=item B<username>

=item B<user_id>

=item B<group_id>

=item B<group_path>

=back

=cut

# Accessors that resolve names, ids or paths
has username => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->id2username });

has user_id => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        $_[0]->config->user_id || $_[0]->username2id;
    },
);

has group_id => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->config->group_id || $_[0]->group2id },
);

has group_path => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return undef unless ($self->group_id);
        return $self->cache->{group_path}->{ $self->{group_id} }
          if $self->cache->{group_path}->{ $self->{group_id} };
        return $self->{group_path} if ($self->{group_path});   # Set if --group
        eval {
            $self->{group_path}
              = $self->api->group_without_projects($self->group_id)
              ->{full_path};
            $self->cache->{group_path}->{ $self->{group_id} }
              = $self->{group_path};
        };
        if ($@) {
            ds_verbose $@;
            ds_warn "Unexistent group " . $self->group_id;
            return undef;
        }
        return $self->{group_path};
    },
);

=back

=head1 METHODS

=over

=item B<run>: main method, load and run command and return Unix result code.

=cut

sub run {
    my ($self, $args) = @_;
    binmode STDOUT, ':utf8';

    # Check group or user id
    my $command = $self->config->command;
    if (my $tmp = cmd_aliases->{$command}) {
        $command = $tmp;
    }
    eval { with "Devscripts::Salsa::$command" };
    if ($@) {
        ds_verbose $@;
        ds_die "Unknown command $command";
        return 1;
    }
    return $self->$command(@ARGV);
}

=back

=head2 Utilities

=over

=item B<levels_name>, B<levels_code>: convert strings to GitLab level codes
(owner, maintainer, developer, reporter and guest)

=cut

sub levels_name {
    my $res = {

        # needs GitLab::API::v4::Constants 0.11
        # no_access  => $GITLAB_ACCESS_LEVEL_NO_ACCESS,
        guest      => $GITLAB_ACCESS_LEVEL_GUEST,
        reporter   => $GITLAB_ACCESS_LEVEL_REPORTER,
        developer  => $GITLAB_ACCESS_LEVEL_DEVELOPER,
        maintainer => $GITLAB_ACCESS_LEVEL_MASTER,
        owner      => $GITLAB_ACCESS_LEVEL_OWNER,
    }->{ $_[1] };
    ds_die "Unknown access level '$_[1]'" unless ($res);
    return $res;
}

sub levels_code {
    return {
        $GITLAB_ACCESS_LEVEL_GUEST     => 'guest',
        $GITLAB_ACCESS_LEVEL_REPORTER  => 'reporter',
        $GITLAB_ACCESS_LEVEL_DEVELOPER => 'developer',
        $GITLAB_ACCESS_LEVEL_MASTER    => 'maintainer',
        $GITLAB_ACCESS_LEVEL_OWNER     => 'owner',
    }->{ $_[1] };
}

=item B<username2id>, B<id2username>: convert username to an id an reverse

=cut

sub username2id {
    my ($self, $user) = @_;
    $user ||= $self->config->user || $self->api->current_user->{id};
    unless ($user) {
        return ds_warn "Token seems invalid";
        return 1;
    }
    unless ($user =~ /^\d+$/) {
        return $self->cache->{user_id}->{$user}
          if $self->cache->{user_id}->{$user};
        my $users = $self->api->users({ username => $user });
        return ds_die "Username '$user' not found"
          unless ($users and @$users);
        ds_verbose "$user id is $users->[0]->{id}";
        $self->cache->{user_id}->{$user} = $users->[0]->{id};
        return $users->[0]->{id};
    }
    return $user;
}

sub id2username {
    my ($self, $id) = @_;
    $id ||= $self->config->user_id || $self->api->current_user->{id};
    return $self->cache->{user}->{$id} if $self->cache->{user}->{$id};
    my $res = eval { $self->api->user($id)->{username} };
    if ($@) {
        ds_verbose $@;
        return ds_die "$id not found";
    }
    ds_verbose "$id is $res";
    $self->cache->{user}->{$id} = $res;
    return $res;
}

=item B<group2id>: convert group name to id

=cut

sub group2id {
    my ($self, $name) = @_;
    $name ||= $self->config->group;
    return unless $name;
    if ($self->cache->{group_id}->{$name}) {
        $self->group_path($self->cache->{group_id}->{$name}->{path});
        return $self->group_id($self->cache->{group_id}->{$name}->{id});
    }
    my $groups = $self->api->group_without_projects($name);
    if ($groups) {
        $groups = [$groups];
    } else {
        $self->api->groups({ search => $name });
    }
    return ds_die "No group found" unless ($groups and @$groups);
    if (scalar @$groups > 1) {
        ds_warn "More than one group found:";
        foreach (@$groups) {
            print <<END;
Id       : $_->{id}
Name     : $_->{name}
Full name: $_->{full_name}
Full path: $_->{full_path}

END
        }
        return ds_die "Set the chosen group id using --group-id.";
    }
    ds_verbose "$name id is $groups->[0]->{id}";
    $self->cache->{group_id}->{$name}->{path}
      = $self->group_path($groups->[0]->{full_path});
    $self->cache->{group_id}->{$name}->{id} = $groups->[0]->{id};
    return $self->group_id($groups->[0]->{id});
}

=item B<project2id>: get id of a project.

=cut

sub project2id {
    my ($self, $project) = @_;
    return $project if ($project =~ /^\d+$/);
    my $res;
    $project = $self->project2path($project);
    if ($self->projectCache->{$project}) {
        ds_debug "use cached id for $project";
        return $self->projectCache->{$project};
    }
    unless ($project =~ /^\d+$/) {
        eval { $res = $self->api->project($project)->{id}; };
        if ($@) {
            ds_debug $@;
            ds_warn "Project $project not found";
            return undef;
        }
    }
    ds_verbose "$project id is $res";
    $self->projectCache->{$project} = $res;
    return $res;
}

=item B<project2path>: get full path of a project

=cut

sub project2path {
    my ($self, $project) = @_;
    return $project if ($project =~ m#/#);
    my $path = $self->main_path;
    return undef unless ($path);
    ds_verbose "Project $project => $path/$project";
    return "$path/$project";
}

=item B<main_path>: build path using given group or user

=cut

sub main_path {
    my ($self) = @_;
    my $path;
    if ($self->config->path) {
        $path = $self->config->path;
    } elsif (my $tmp = $self->group_path) {
        $path = $tmp;
    } elsif ($self->user_id) {
        $path = $self->username;
    } else {
        ds_warn "Unable to determine project path";
        return undef;
    }
    return $path;
}

# GitLab::API::v4 does not permit to call /groups/:id with parameters.
# It takes too much time for the "debian" group, since it returns the list of
# all projects together with all the details of the projects
sub GitLab::API::v4::group_without_projects {
    my $self = shift;
    return $self->_call_rest_client('GET', 'groups/:group_id', [@_],
        { query => { with_custom_attributes => 0, with_projects => 0 } });
}

1;

=back

=head1 AUTHOR

Xavier Guimard E<lt>yadd@debian.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2018, Xavier Guimard E<lt>yadd@debian.orgE<gt>
