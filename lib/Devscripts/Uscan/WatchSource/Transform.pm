package Devscripts::Uscan::WatchSource::Transform;

use Moo::Role;
use Devscripts::Uscan::Output;

use constant {
    ANY_VERSION    => '(?:[-_]?[Vv]?(\d[\-+\.:\~\da-zA-Z]*))',
    STABLE_VERSION => '(?:[-_]?[Vv]?((?:[1-9]\d*)(?:\.\d+){2}))',
    # From semver.org
    SEMANTIC_VERSION =>
'(?:[-_]?[Vv]?((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?:[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?))',
    ARCHIVE_EXT =>
      '(?i)(?:\.(?:tar\.xz|tar\.bz2|tar\.gz|tar\.zstd?|zip|tgz|tbz|txz))',
    DEB_EXT => '(?:[\+~](debian|dfsg|ds|deb)(\.)?(\d+)?$)',

    ALIASES => {
        date           => 'gitdate',
        pretty         => 'gitpretty',
        versionregex   => 'matchingpattern',
        versionpattern => 'matchingpattern',
    },
};
use constant SIGNATURE_EXT => ARCHIVE_EXT . '(?:\.(?:asc|pgp|gpg|sig|sign))';

sub transformWatchSource {
    my ($self, $args) = @_;

    foreach my $watchSource (@{ $self->watchOptions }) {

        foreach my $alias (keys %{&ALIASES}) {
            if (defined $watchSource->{$alias}) {
                my $nk = ALIASES->{$alias};
                if (defined $watchSource->{$nk}) {
                    uscan_die "Key $nk is declared and its alias $nk too";
                    return;
                }
                $watchSource->{$nk} = delete $watchSource->{$alias};
            }
        }

        my $templates;
        while ($watchSource->{template}) {
            if ($watchSource->{template} !~ /^\w+$/) {
                uscan_die qq'Malformed template "$watchSource->{template}"';
                return;
            }
            $watchSource->{template} = ucfirst(lc $watchSource->{template});
            my $pkg = "Devscripts::Uscan::Templates::$watchSource->{template}";
            $templates->{current} = $watchSource->{template};
            eval "require $pkg";
            if ($@) {
                uscan_die qq'Unknown template "$watchSource->{template}": $@';
            }
            my $transform = eval "$pkg->can('transform')";
            if (!$transform) {
                uscan_die
qq'Template "$watchSource->{template}" has no transform function';
                return;
            }
            my $tmp = eval { $transform->($watchSource) };
            if ($@) {
                uscan_die "$pkg failed: $@";
                return;
            }
            unless ($tmp) {
                uscan_die "$pkg didn't return a watchsource";
                return;
            }
            $watchSource = $tmp;
            if (    $watchSource->{template}
                and $templates->{current} eq $watchSource->{template}) {
                uscan_debug "$pkg missed to delete template field";
                delete $watchSource->{template};
                last;
            }
            if ($watchSource->{template}) {
                $watchSource->{template}
                  = ucfirst(lc $watchSource->{template});
                if ($templates->{ $watchSource->{template} }) {
                    uscan_die
"Template look detected ($watchSource->{template} recalled)";
                    return;
                }
                $templates->{ $watchSource->{template} }++;
            }
        }

        foreach my $k (keys %$watchSource) {
            # Handle @FOO@ substitutions
            $watchSource->{$k} =~ s/\@PACKAGE\@/$args->{package}/g;
            $watchSource->{$k} =~ s/\@ANY_VERSION\@/ANY_VERSION/ge;
            $watchSource->{$k} =~ s/\@STABLE_VERSION\@/STABLE_VERSION/ge;
            $watchSource->{$k} =~ s/\@SEMANTIC_VERSION\@/SEMANTIC_VERSION/ge;
            $watchSource->{$k} =~ s/\@ARCHIVE_EXT\@/ARCHIVE_EXT/ge;
            $watchSource->{$k} =~ s/\@SIGNATURE_EXT\@/SIGNATURE_EXT/ge;
            $watchSource->{$k} =~ s/\@DEB_EXT\@/DEB_EXT/ge;
            $watchSource->{$k} =~ s/\@COMPONENT\@/$watchSource->{component}/g;

            if ($watchSource->{$k} eq 'auto') {
                # dversionmangle=auto is replaced by s/@DEB_EXT@//
                if ($k eq 'dversionmangle') {
                    $watchSource->{$k} = 's/' . DEB_EXT . '//';
                }
                # filenamemangle=auto is replaced by
                # s/.*?(@ANY_VERSION@@ARCHIVE_EXT@)/@PACKAGE@-$1/
                # But @PACKAGE@ is replaced by @PACKAGE@-@COMPONENT@ when
                # watch source is a component
                elsif ($k eq 'filenamemangle') {
                    $watchSource->{$k}
                      = 's/.*?[-_]*('
                      . ANY_VERSION
                      . ARCHIVE_EXT . ')/'
                      . $args->{package}
                      . (
                        $watchSource->{component}
                        ? '-' . $watchSource->{component}
                        : ''
                      ) . '-$1/';
                } elsif ($k eq 'uversionmangle') {
                    $watchSource->{$k}
                      = 's/(\d)[_\.\-\+]?((?:RC|rc|pre|dev|beta|alpha)\d*)$/$1~$2/';
                }
            }
        }

        # When global "Version-Schema" is "checksum", the main watch source has
        # to be "group"
        if (    $watchSource->{versionschema}
            and $watchSource->{versionschema} eq 'checksum'
            and !$watchSource->{component}) {
            $watchSource->{versionschema} = 'group';
        }
    }
    return 1;
}

1;
