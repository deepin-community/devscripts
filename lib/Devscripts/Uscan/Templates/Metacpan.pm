package Devscripts::Uscan::Templates::Metacpan;

use strict;

sub transform {
    my $watchSource = shift;
    delete $watchSource->{template};
    $watchSource->{mode} = 'metacpan';
    my $dist = delete $watchSource->{dist} // '';
    $dist =~ s/::/-/g;
    $watchSource->{source} ||= $dist;
    die 'Missing Dist' unless $watchSource->{source};
    $watchSource->{matchingpattern}
      ||= "https://cpan.metacpan.org/.*$watchSource->{source}-\@ANY_VERSION@";
    $watchSource->{pgpmode} ||= 'none';
    return $watchSource;
}

1;
