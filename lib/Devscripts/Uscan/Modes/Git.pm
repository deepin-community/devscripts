package Devscripts::Uscan::Modes::Git;

use strict;
use Cwd qw/abs_path cwd/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::Modes::_vcs;
use Dpkg::IPC;
use File::Path 'remove_tree';
use Moo::Role;

######################################################
# search $newfile $newversion (git mode/versionless)
######################################################
sub git_search {
    my ($self) = @_;
    my ($newfile, $newversion, $mangled_newversion);
    if ($self->versionless) {
        $newfile = $self->parse_result->{filepattern}; # HEAD or heads/<branch>
        my @args   = ();
        my $curdir = cwd();

        push(@args, '--quiet') if not $verbose;
        push(@args, '--bare')  if not $self->git->{modules};

        if ($self->gitpretty eq 'describe') {
            $self->git->{mode} = 'full';
        }

        if ($self->git->{mode} eq 'shallow') {
            push(@args, '--depth=1');
            $self->downloader->gitrepo_state(1);
        } else {
            $self->downloader->gitrepo_state(2);
        }

        if ($newfile ne 'HEAD') {
            $newfile = s&^heads/&&;    # Set to <branch>
            push(@args, '-b', "$newfile");
        }

        # clone main repository
        uscan_exec(
            'git', 'clone', @args,
            $self->parse_result->{base},
            "$self->{downloader}->{destdir}/" . $self->gitrepo_dir
        );

        chdir "$self->{downloader}->{destdir}/$self->{gitrepo_dir}";

        if ($self->gitpretty eq 'describe') {
            # use unannotated tags to be on safe side
            uscan_debug "git describe --tags";
            spawn(
                exec       => ['git', 'describe', '--tags'],
                wait_child => 1,
                to_string  => \$newversion
            );
            $newversion =~ s/-/./g;
            chomp($newversion);
            $mangled_newversion = $newversion;
            if (
                mangle(
                    $self->watchfile,            'uversionmangle:',
                    \@{ $self->uversionmangle }, \$mangled_newversion
                )
            ) {
                return undef;
            }
        } else {
            my $tmp = $ENV{TZ};
            $ENV{TZ} = 'UTC';
            @args = ('-1');
            push(@args, '-b', $newfile) if ($newfile ne 'HEAD');
            push(@args, "--date=format-local:$self->{gitdate}");
            push(@args, "--no-show-signature");
            push(@args, "--pretty=$self->{gitpretty}");

            uscan_debug "git log " . join(' ', @args);

            spawn(
                exec       => ['git', 'log', @args],
                wait_child => 1,
                to_string  => \$newversion
            );
            $ENV{TZ} = $tmp;
            chomp($newversion);
            $mangled_newversion = $newversion;
        }
        chdir "$curdir";
    }
    ################################################
    # search $newfile $newversion (git mode w/tag)
    ################################################
    elsif ($self->mode eq 'git') {
        my @args = ('ls-remote', $self->parse_result->{base});
        # Try to use local upstream branch if available
        if (-d '.git') {
            my $out;
            eval {
                spawn(
                    exec       => ['git', 'remote', '--verbose', 'show'],
                    wait_child => 1,
                    to_string  => \$out
                );
            };
            # Check if git repo found in debian/watch exists in
            # `git remote show` output
            if ($out and $out =~ /^(\S+)\s+\Q$self->{parse_result}->{base}\E/m)
            {
                $self->downloader->git_upstream($1);
                uscan_warn
                  "Using $self->{downloader}->{git_upstream} remote origin";
                # Found, launch a "fetch" to be up to date
                spawn(
                    exec => ['git', 'fetch', $self->downloader->git_upstream],
                    wait_child => 1
                );
                @args = ('show-ref');
            }
        }
        ($mangled_newversion, $newversion, $newfile)
          = get_refs($self, ['git', @args], qr/^\S+\s+([^\^\{\}]+)$/, 'git');
        return undef if !defined $newversion;
    }
    return ($mangled_newversion, $newversion, $newfile);
}

sub git_upstream_url {
    my ($self) = @_;
    my $upstream_url
      = $self->parse_result->{base} . ' ' . $self->search_result->{newfile};
    return $upstream_url;
}

*git_newfile_base = \&Devscripts::Uscan::Modes::_vcs::_vcs_newfile_base;

sub git_clean {
    my ($self) = @_;

    # If git cloned repo exists and not --debug ($verbose=2) -> remove it
    if (    $self->downloader->gitrepo_state > 0
        and $verbose < 2
        and !$self->downloader->git_upstream) {
        my $err;
        uscan_verbose "Removing git repo ($self->{downloader}->{destdir}/"
          . $self->gitrepo_dir . ")";
        remove_tree "$self->{downloader}->{destdir}/" . $self->gitrepo_dir,
          { error => \$err };
        if (@$err) {
            local $, = "\n\t";
            uscan_warn "Errors during git repo clean:\n\t@$err";
        }
        $self->downloader->gitrepo_state(0);
    } else {
        uscan_debug "Keep git repo ($self->{downloader}->{destdir}/"
          . $self->gitrepo_dir . ")";
    }
    return 0;
}

1;
