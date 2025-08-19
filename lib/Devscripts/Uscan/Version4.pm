package Devscripts::Uscan::Version4;

use strict;
use Devscripts::Uscan::Config;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Config;
use IO::String;

my %order = (
    Component          => 1,
    Template           => 2,
    Source             => 3,
    'Matching-Pattern' => 4,
);

# Prepare attributs name changes between version 4 and version 5
our %RENAMED = ();

# Template transformers
my @templates = (
    # Metacpan
    #
    # The following URLs are grouped here with regexp-asseble(1):
    # https://metacpan.org/release/(\w[\w\-\:]*\w)
    # https://metacpan.org/dist/(\w[\w\-\:]*\w)
    # https://fastapi.metacpan.org/v1/release/(\w[\w\-\:]*\w)
    [
qr#https:\/\/(?:fastapi.metacpan.org\/v1\/release|metacpan.org\/(?:release|dist))\/(\w[\w\-\:]*\w)#
          => sub {
            my ($res) = @_;
            $res->{Dist}     = $1;
            $res->{Template} = 'Metacpan';
            delete $res->{$_} foreach (qw(Source Matching-Pattern));
            return $res;
        }
    ],
    # Github
    [
        qr#https://github.com/([^/]+)/([^/]+)/(releases|tags)# => sub {
            my ($res) = @_;
            $res->{Template} = 'Github';
            $res->{Owner}    = $1;
            $res->{Project}  = $2;
            delete $res->{$_}
              foreach (
                qw(Source Matching-Pattern Downloadurlmangle Filenamemangle));
            return $res;
        }
    ],
);

sub new {
    my ($class, $file, $config) = @_;
    local $/ = "\n";
    my ($WATCH);
    unless (open $WATCH, '<', $file) {
        uscan_die "could not open $file: $!";
    }
    my ($newContent, $watch_version);
    my $comments = '';

    # Taken from uscan 2.21.6
    while (<$WATCH>) {
        my $res = {};
        if (s/^\s*\#/#/) {
            $comments .= $_;
            next;
        }
        next if /^\s*$/;
        s/^\s*//;
        my ($base, $filepattern, $lastversion, $action);

      CHOMP:

        # Reassemble lines split using \
        chomp;
        if (s/(?<!\\)\\$//) {
            if (eof($WATCH)) {
                uscan_warn "$file ended with \\; skipping last line";
                last;
            }
            if ($watch_version > 3) {

                # drop leading \s only if version 4
                my $nextline = <$WATCH>;
                $nextline =~ s/^\s*//;
                $_ .= $nextline;
            } else {
                $_ .= <$WATCH>;
            }
            goto CHOMP;
        }

        # "version" must be the first field
        if (!$watch_version) {

            # Looking for "version" field.
            if (/^version\s*=\s*(\d+)(\s|$)/) {    # Found
                $watch_version = $1;

                # Note that version=1 watchfiles have no "version" field so
                # authorizated values are >= 2 and <= CURRENT_WATCHFILE_VERSION
                if ($watch_version < 2 or $watch_version > 4) {
                    # "version" field found but has no authorizated value
                    uscan_warn "$file version number is unrecognised";
                }

                # Next line
                next;
            } elsif (/^Version: \d+$/) {
                die "$file seems to be already updated, aborting";
            }

            # version=1 is deprecated
            else {
                $watch_version = 1;
            }
        }
        # "version" is fixed, parsing lines now

        # VERSION 1
        if ($watch_version == 1) {
            # Handle shell \\ -> \
            s/\\\\/\\/g if $watch_version == 1;
            my ($site, $dir);
            ($site, $dir, $filepattern, $lastversion, $action) = split ' ',
              $_, 4;
            if (  !$lastversion
                or $site =~ /\(.*\)/
                or $dir  =~ /\(.*\)/) {
                uscan_warn <<EOF;
there appears to be a version 2 format line in
the version 1 watch file $file;
Have you forgotten a 'version=2' line at the start, perhaps?
Skipping the line: $_
EOF
                next;
            }
            if ($site !~ m%\w+://%) {
                $site = "ftp://$site";
                if ($filepattern !~ /\(.*\)/) {

                  # watch_version=1 and old style watch file;
                  # pattern uses ? and * shell wildcards; everything from the
                  # first to last of these metachars is the pattern to match on
                    $filepattern =~ s/(\?|\*)/($1/;
                    $filepattern =~ s/(\?|\*)([^\?\*]*)$/$1)$2/;
                    $filepattern =~ s/\./\\./g;
                    $filepattern =~ s/\?/./g;
                    $filepattern =~ s/\*/.*/g;
                }
            }

            # Merge site and dir
            $base = "$site/$dir/";
            $base =~ s%(?<!:)//%/%g;
            $base =~ m%^(\w+://[^/]+)%;
            $site = $1;
            #$pattern = $filepattern;

            # Check $filepattern is OK
            if ($filepattern !~ /\(.*\)/) {
                uscan_warn "Filename pattern missing version delimiters ()\n"
                  . "  in $file, skipping:\n  $_";
                next;
            }

        } else {
            if (s/^opt(?:ion)?s\s*=\s*//) {
                my $opts;
                if (s/^"(.*?)"(?:\s+|$)//) {
                    $opts = $1;
                } elsif (s/^([^"\s]\S*)(?:\s+|$)//) {
                    $opts = $1;
                } else {
                    uscan_warn
                      "malformed opts=... in watch file, skipping line:\n$_";
                    next;
                }
                uscan_debug "opts: $opts";
                uscan_debug "line: $_";
                if ($opts =~ s/(?:^|,)\s*user-?agent\s*=\s*(.+?)\s*$//) {
                    $res->{'User-Agent'} = $1;
                }
                my @opts = sort split /,/, $opts;
                foreach my $opt (@opts) {
                    next unless $opt =~ /\S/;
                    next
                      if $opt =~ /^(?:nopas(?:sive|v)|pas(?:sive|v)|active)$/;
                    uscan_debug "Parsing $opt";
                    unless ($opt =~ /^\s*([\w\-]+)(?:\s*=\s*(.*?))?\s*$/) {
                        uscan_warn "Unable to parse '$opt', skipping";
                        next;
                    }
                    my ($k, $v) = ($1, $2);
                    $k = ucfirst $k;
                    $k =~ s/-(.)/'-'.uc($1)/ge;
                    $res->{$k} = defined $v ? $v : 'yes';
                }
            }
            ($base, $filepattern, $lastversion, $action) = split /\s+/, $_, 4;
            if ($base =~ s%/([^/]*(?:\@.*\@|\([^/]*\))[^/]*)$%/%) {

               # Last component of $base has a pair of parentheses, so no
               # separate filepattern field; we remove the filepattern from the
               # end of $base and rescan the rest of the line
                $filepattern = $1;
                (undef, $lastversion, $action) = split /\s+/, $_, 3;
            }
        }
        # End: Taken form uscan 2.21.6

        if ($lastversion) {
            if ($lastversion =~ m/^(?:group|checksum|ignore)$/) {
                $res->{'Version-Schema'} = $lastversion;
            } elsif ($lastversion eq 'debian') {
            } elsif ($lastversion eq 'prev') {
                $res->{'Version-Schema'} = 'previous';
            } else {
                $res->{'Version-Constraint'} = $lastversion;
            }
        }
        $res->{Source}             = $base;
        $res->{'Matching-Pattern'} = $filepattern
          if defined $filepattern and $filepattern ne 'debian';
        $res->{'Update-Script'} = $action if defined $action;

        # Use template if --update-watchfile and if possible
        if ($config and $config->{update_watchfile}) {
            foreach my $tmpl (@templates) {
                $res = $tmpl->[1]->($res) if $res->{Source} =~ $tmpl->[0];
            }
        }

        # Line was split, storing it now
        $newContent .= $comments . join(
            "\n",
            map { ($RENAMED{ lc $_ } || $_) . ": $res->{$_}" } sort {
                $order{$a} ? ($order{$b} ? ($order{$a} <=> $order{$b}) : -1)
                  : $order{$b} ? 1
                  : $a cmp $b
            } keys %$res
        ) . "\n\n";
        $comments = '';
    }

    close $WATCH or uscan_warn "problems reading $file: $!";

    $newContent =~ s/\n\n$/\n/s;
    $newContent
      = "Version: "
      . $Devscripts::Uscan::Config::CURRENT_WATCHFILE_VERSION
      . "\n\n$newContent";
    my $self = IO::String->new($newContent);
    uscan_verbose "File $file converted into << ==EOF==\n$newContent\n==EOF==";
    return $self;
}

1;
__END__

=pod

=head1 NAME

Devscripts::Uscan::Version4 - convert on-the-fly old formatted debian/watch to format 5

=head1 SYNOPSIS

  use Devscripts::Uscan::Version4;
  my $filehandle = Devscripts::Uscan::Version4->new("debian/watch");
  print while (<$filehandle>);

=head1 DESCRIPTION

Uscan class to convert on the fly a old formatted debian/watch.

=head2 Functioning

Devscripts::Uscan::Version4::new() reads the given watchfile, transform it and
returns a L<IO::String> object.

=head1 SEE ALSO

L<uscan>, L<Devscripts::Config>

=head1 AUTHOR

Xavier Guimard E<lt>yadd@debian.orgE<gt>.

=head1 COPYRIGHT AND LICENSE

Xavier Guimard <yadd@debian.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
