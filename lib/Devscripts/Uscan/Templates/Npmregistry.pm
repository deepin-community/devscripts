package Devscripts::Uscan::Templates::Npmregistry;

use strict;

sub transform {
    my $watchSource = shift;
    delete $watchSource->{template};
    my $dist = delete $watchSource->{dist} // '';
    my $name = $dist;
    $name =~ s#.*/##;
    $watchSource->{source} ||= "https://registry.npmjs.org/$dist";
    $watchSource->{matchingpattern}
      ||= "https://registry.npmjs.org/$dist/-/$name-\@ANY_VERSION@\@ARCHIVE_EXT@";
    $watchSource->{uversionmangle} ||= 'auto';
    $watchSource->{filenamemangle} ||= 'auto';
    $watchSource->{pgpmode}        ||= 'none';
    $watchSource->{searchmode}     ||= 'plain';
    return $watchSource;
}

1;
