package Devscripts::Salsa::path;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use Moo::Role;

sub path {
    my ($self, $path) = @_;
    if (my $remote = $self->localPath2projectPath($path)) {
        print "$remote\n";
        return 0;
    }
    return ds_die "Not found";
}

1;
