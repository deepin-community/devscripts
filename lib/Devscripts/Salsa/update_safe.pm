# launches check_projects and launch update_projects if user agrees with this changes
package Devscripts::Salsa::update_safe;

use strict;
use Devscripts::Output;
use Moo::Role;

with 'Devscripts::Salsa::check_repo';     # check_projects
with 'Devscripts::Salsa::update_repo';    # update_projects

sub update_safe {
    my $self = shift;
    my ($res, $fails) = $self->_check_repo(@_);
    return 0 unless ($res);
    return $res
      if (ds_prompt("$res projects misconfigured, update them ? (Y/n) ")
        =~ refuse);
    $Devscripts::Salsa::update_repo::prompt = 0;
    return $self->_update_repo(@$fails);
}

1;
