package Devscripts::Uscan::Templates::Github;

use strict;

sub transform {
    my $watchSource = shift;
    delete $watchSource->{template};
    my $owner   = delete $watchSource->{owner};
    my $project = delete $watchSource->{project};
    die 'Missing owner'   unless $owner;
    die 'Missing project' unless $project;

    $watchSource->{source}
      ||= "https://api.github.com/repos/$owner/$project/git/matching-refs/tags/";
    $watchSource->{matchingpattern}
      ||= 'https://api.github.com/repos/[^/]+/[^/]+/git/refs/tags/(?:[^/]+\-)?@ANY_VERSION@';
    $watchSource->{downloadurlmangle}
      ||= 's%(api.github.com/repos/[^/]+/[^/]+)/git/refs/%$1/tarball/refs/%g';
    $watchSource->{filenamemangle}
      ||= 's%.*/(?:[^/]+\-)?@ANY_VERSION@%@PACKAGE@-$1.tar.gz%';
    $watchSource->{searchmode} ||= 'plain';
    $watchSource->{pgpmode}    ||= 'none';
    return $watchSource;
}

1;
