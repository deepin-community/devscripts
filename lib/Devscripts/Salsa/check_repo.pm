# Parses repo to check if parameters are well set
package Devscripts::Salsa::check_repo;

use strict;
use Devscripts::Output;
use Digest::MD5  qw(md5_hex);
use Digest::file qw(digest_file_hex);
use LWP::UserAgent;
use Moo::Role;

with "Devscripts::Salsa::Repo";

sub check_repo {
    my $self = shift;
    my ($res) = $self->_check_repo(@_);
    return $res;
}

sub _url_md5_hex {
    my $url = shift;
    my $ua  = LWP::UserAgent->new;
    my $res = $ua->get($url, "User-Agent" => "Devscripts/2.22.3",);
    if (!$res->is_success) {
        return undef;
    }
    return Digest::MD5::md5_hex($res->content);
}

sub _check_repo {
    my ($self, @reponames) = @_;
    my $res = 0;
    my @fail;
    unless (@reponames or $self->config->all or $self->config->all_archived) {
        @reponames = ($self->localPath2projectPath);
        unless (@reponames) {
            ds_warn "Usage $0 check_repo <--all|--all-archived|names>";
            return 1;
        }
    }
    if (@reponames and $self->config->all) {
        ds_warn "--all with a reponame makes no sense";
        return 1;
    }
    if (@reponames and $self->config->all_archived) {
        ds_warn "--all-archived with a reponame makes no sense";
        return 1;
    }
    # Get repo list from Devscripts::Salsa::Repo
    my @repos = $self->get_repo(0, @reponames);
    return @repos unless (ref $repos[0]);
    foreach my $repo (@repos) {
        my @err;
        my ($id, $name) = @$repo;
        my $project = eval { $self->api->project($id) };
        unless ($project) {
            ds_debug $@;
            ds_warn "Project $name not found";
            next;
        }
        ds_debug "Checking $name ($id)";
        # check description
        my %prms           = $self->desc($name);
        my %prms_multipart = $self->desc_multipart($name);
        if ($self->config->desc) {
            $project->{description} //= '';
            push @err, "bad description: $project->{description}"
              if ($prms{description} ne $project->{description});
        }
        # check build timeout
        if ($self->config->desc) {
            $project->{build_timeout} //= '';
            push @err, "bad build_timeout: $project->{build_timeout}"
              if ($prms{build_timeout} ne $project->{build_timeout});
        }
        # check features (w/permission) & ci config
        foreach (qw(
            analytics_access_level
            auto_devops_enabled
            builds_access_level
            ci_config_path
            container_registry_access_level
            environments_access_level
            feature_flags_access_level
            forking_access_level
            infrastructure_access_level
            issues_access_level
            lfs_enabled
            merge_requests_access_level
            monitor_access_level
            packages_enabled
            pages_access_level
            releases_access_level
            remove_source_branch_after_merge
            repository_access_level
            request_access_enabled
            requirements_access_level
            security_and_compliance_access_level
            service_desk_enabled
            snippets_access_level
            wiki_access_level
            )
        ) {
            my $helptext = '';
            $helptext = ' (enabled)'
              if (defined $prms{$_} and $prms{$_} eq 1);
            $helptext = ' (disabled)'
              if (defined $prms{$_} and $prms{$_} eq 0);
            push @err, "$_ should be $prms{$_}$helptext"
              if (defined $prms{$_}
                and (!defined($project->{$_}) or $project->{$_} ne $prms{$_}));
        }
        # only public projects are accepted
        push @err, "Project visibility: $project->{visibility}"
          unless ($project->{visibility} eq "public");
        # Default branch
        if ($self->config->rename_head) {
            push @err, "Default branch: $project->{default_branch}"
              if ($project->{default_branch} ne $self->config->dest_branch);
        }
        # Webhooks (from Devscripts::Salsa::Hooks)
        my $hooks = $self->enabled_hooks($id);
        unless (defined $hooks) {
            ds_warn "Unable to get $name hooks";
            next;
        }
        # check avatar's path
        if ($self->config->avatar_path) {
            my ($md5_file, $md5_url) = "";
            if ($prms_multipart{avatar}) {
                ds_verbose "Calculating local avatar checksum";
                $md5_file = digest_file_hex($prms_multipart{avatar}, "MD5")
                  or die "$prms_multipart{avatar} failed md5: $!";
                if (    $project->{avatar_url}
                    and $project->{visibility} eq "public") {
                    ds_verbose "Calculating remote avatar checksum";
                    $md5_url = _url_md5_hex($project->{avatar_url})
                      or die "$project->{avatar_url} failed md5: $!";
                    # Will always force avatar if it can't detect
                } elsif ($project->{avatar_url}) {
                    ds_warn
"$name has an avatar, but is set to $project->{visibility} project visibility thus unable to remotely check checksum";
                }
                push @err, "Will set the avatar to be: $prms_multipart{avatar}"
                  if (not length $md5_url or $md5_file ne $md5_url);
            }
        }
        # KGB
        if ($self->config->kgb and not $hooks->{kgb}) {
            push @err, "kgb missing";
        } elsif ($self->config->disable_kgb and $hooks->{kgb}) {
            push @err, "kgb enabled";
        } elsif ($self->config->kgb) {
            push @err,
              "bad irc channel: "
              . substr($hooks->{kgb}->{url},
                length($self->config->kgb_server_url))
              if $hooks->{kgb}->{url} ne $self->config->kgb_server_url
              . $self->config->irc_channel->[0];
            my @wopts = @{ $self->config->kgb_options };
            my @gopts = sort @{ $hooks->{kgb}->{options} };
            my $i     = 0;
            while (@gopts and @wopts) {
                my $a;
                $a = ($wopts[0] cmp $gopts[0]);
                if ($a == -1) {
                    push @err, "Missing KGB option " . shift(@wopts);
                } elsif ($a == 1) {
                    push @err, 'Unwanted KGB option ' . shift(@gopts);
                } else {
                    shift @wopts;
                    shift @gopts;
                }
            }
            push @err, map { "Missing KGB option $_" } @wopts;
            push @err, map { "Unwanted KGB option $_" } @gopts;
        }
        # Email-on-push
        if ($self->config->email
            and not($hooks->{email} and %{ $hooks->{email} })) {
            push @err, "email-on-push missing";
        } elsif (
            $self->config->email
            and $hooks->{email}->{recipients} ne join(
                ' ',
                map {
                    my $a = $_;
                    my $b = $name;
                    $b =~ s#.*/##;
                    $a =~ s/%p/$b/;
                    $a
                } @{ $self->config->email_recipient })
        ) {
            push @err, "bad email recipients " . $hooks->{email}->{recipients};
        } elsif ($self->config->disable_email and $hooks->{kgb}) {
            push @err, "email-on-push enabled";
        }
        # Irker
        if ($self->config->irker and not $hooks->{irker}) {
            push @err, "irker missing";
        } elsif ($self->config->irker
            and $hooks->{irker}->{recipients} ne
            join(' ', map { "#$_" } @{ $self->config->irc_channel })) {
            push @err, "bad irc channel: " . $hooks->{irker}->{recipients};
        } elsif ($self->config->disable_irker and $hooks->{irker}) {
            push @err, "irker enabled";
        }
        # Tagpending
        if ($self->config->tagpending and not $hooks->{tagpending}) {
            push @err, "tagpending missing";
        } elsif ($self->config->disable_tagpending
            and $hooks->{tagpending}) {
            push @err, "tagpending enabled";
        }
        # report errors
        if (@err) {
            $res++;
            push @fail, $name;
            print "$name:\n";
            print "\t$_\n" foreach (@err);
        } else {
            ds_verbose "$name: OK";
        }
    }
    return ($res, \@fail);
}

1;
