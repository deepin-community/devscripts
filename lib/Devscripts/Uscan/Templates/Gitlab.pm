package Devscripts::Uscan::Templates::Gitlab;

use strict;

sub transform {
    my $watchSource = shift;
    delete $watchSource->{template};
    my $url = delete $watchSource->{dist};
    die 'Missing dist' unless $url;
    die "Bad dist: $url" unless $url =~ m#^https?://#;
    $url =~ s#/+$##;
    $watchSource->{source}          ||= $url;
    $watchSource->{matchingpattern} ||= '.*@ANY_VERSION@';
    $watchSource->{filenamemangle}  ||= (
        $watchSource->{component}
        ? 's%.*?@ANY_VERSION@$%@PACKAGE@-@COMPONENT@-$1.tar.gz%'
        : 's%.*?@ANY_VERSION@$%@PACKAGE@-$1.tar.gz%'
    );
    $watchSource->{uversionmangle} = 'auto';
    $watchSource->{pgpmode} ||= 'none';
    $watchSource->{mode}    ||= 'gitlab';
    return $watchSource;
}

1;
