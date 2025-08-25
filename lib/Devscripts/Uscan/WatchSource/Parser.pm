package Devscripts::Uscan::WatchSource::Parser;

use Moo::Role;
use Devscripts::Uscan::Output;

sub parseWatchFile {
    my ($self, $watchFileHandle, $args) = @_;
    # Read in paragraph mode
    local $/ = "";
    my $map = sub {
        return map {
            my @lines = split /\n/, $_;
            my @res;
            foreach my $line (@lines) {
                # Skip comments and blank lines
                next if $line =~ /^\s*(?:#.*)$/;
                unless ($line =~ /^([\w\-]+)\s*:\s*(.*?)\s*$/) {
                    die "Unable to parse line '$line', skipping";
                }
                my ($k, $v) = (lc($1), $2);
                $k =~ s/-//g;
                push @res, $k, $v;
            }
            push @res, _raw => $_;
            return {@res};
        } @_;
    };
    $self->commonOpts($map->($watchFileHandle->getline));
    unless (%{ $self->commonOpts }) {
        die "Unable to parse $args->{watchfile} empty header";
    }
    unless ($self->commonOpts->{version}) {
        die 'Missing "Version" field in header, skipping '
          . $args->{watchfile};
    }
    unless ($self->commonOpts->{version} >= 5) {
        die
"Malformed file $args->{watchfile}, version $self->{commonOpts}->{version} is lower than 5";
    }
    if ($self->commonOpts->{version}
        > $Devscripts::Uscan::Config::CURRENT_WATCHFILE_VERSION) {
        die
"$args->{watchfile} uses a newer version ($self->{commonOpts}->{version}) than supported ("
          . $Devscripts::Uscan::Config::CURRENT_WATCHFILE_VERSION
          . '), skipping this file';
    }
    $self->watch_version($self->commonOpts->{version});
    if ($self->commonOpts->{untrackable}) {
        uscan_warn "Untrackable project: " . $self->commonOpts->{untrackable};
        return;
    }
    my $line;
    my $found;
    while (defined($line = $watchFileHandle->getline)) {
        $found++;
        my $watchOptions = $map->($line);
        unless ($watchOptions->{source} || $watchOptions->{template}) {
            uscan_warn
"The following paragraph isn't well formatted, skipping it: << ==EOF==\n"
              . $watchOptions->{_raw}
              . "==EOF==\n";
            next;
        }
        foreach my $k (keys %{ $self->commonOpts }) {
            $watchOptions->{$k} //= $self->commonOpts->{$k};
        }

        push @{ $self->watchOptions }, $watchOptions;
    }
    if (!$found
        and ($self->commonOpts->{source} or $self->commonOpts->{template})) {
        push @{ $self->watchOptions },
          {
            map  { ($_ => $self->commonOpts->{$_}) }
            grep { $_ ne 'version' } keys %{ $self->commonOpts } };
    }
}

1;
