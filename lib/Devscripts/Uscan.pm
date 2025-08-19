package Devscripts::Uscan;

use strict;
use warnings;
use Cwd qw/cwd/;
use Exporter 'import';
use Devscripts::Uscan::Config;
use Devscripts::Uscan::FindFiles;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::WatchFile;

our @EXPORT = (qw(uscan process_watchfile));

sub uscan {
    # Reset global variables
    %Devscripts::Uscan::WatchLine::already_downloaded = ();
    Devscripts::Uscan::Output::reset();

    # Initialize configuration
    my $config = Devscripts::Uscan::Config->new->parse;
    if ($dehs) {
        uscan_verbose "The --dehs option enabled.\n"
          . "        STDOUT = XML output for use by other programs\n"
          . "        STDERR = plain text output for human\n"
          . "        Use the redirection of STDOUT to a file to get the clean XML data";
    }

    my $res = 0;

    # Search for watchfiles
    my @wf = find_watch_files($config);
    foreach (@wf) {

        # Read watchfiles
        my ($tmp) = process_watchfile($config, @$_);
        $res ||= $tmp;

        # Are there any warnings to give if we're using dehs?
        dehs_output if ($dehs);
    }

    uscan_verbose "Scan finished";
    return ($res, $found);
}

sub process_watchfile {
    my ($config, $pkg_dir, $package, $version, $watchfile) = @_;
    my $opwd = cwd();
    chdir $pkg_dir;

    my $wf = Devscripts::Uscan::WatchFile->new({
        config      => $config,
        package     => $package,
        pkg_dir     => $pkg_dir,
        pkg_version => $version,
        watchfile   => $watchfile,
    });
    return ($wf->status, $found) if ($wf->status);

    my $res = $wf->process_lines;
    chdir $opwd;
    return ($res, $found);
}

1;
__END__

=head1 NAME

Devscripts::Uscan - Main L<uscan> library

=head1 SYNOPSIS

  use Devscripts::Uscan;
  my ($res, $found) = uscan();
  exit($res ? $res : $found ? 0 : 1);

=head1 DESCRIPTION

Devscripts::Uscan is the main library called by L<uscan>

=head2 EXPORT

This functions are automatically imported:

=head3 B<uscan()>

Parse watch files and return two values:

=over

=item * B<$res>: the exit code. 0 if nothing wrong happened.

=item * B<$found>: return the number of new upstream found.

=back

=head3 B<process_watchfile($config, $pkg_dir, $package, $version, $watchfile)>

Read given watch file and does L<uscan> job.

=head4 Arguments

=over

=item * B<$config>: a L<Devscripts::Uscan::Config> object

=item * B<$pkg_dir>: root of the Debian source directory

=item * B<$package>: name of the package

=item * B<$version>: current Debian version of the package

=item * B<$watchfile>: path to the watch file

=back

=head4 Returned values

B<process_watchfile()> returns 2 values:

=over

=item * B<$res>: the exit status. 0 if nothing wrong happened.

=item * B<$found>: number of upstream updates found.

B<Important>: this value is a cumulative one. If you want to call
B<process_watchfile()> more than one time and want to check this value for
the current watch file, you have to reset it using the global B<$found>
variable provided by L<Devscripts::Uscan::Output>:

  use Devscripts::Uscan::Output;
  # Loop
  my $res;
  while (XX) {
    # ...
    $found = 0;
    $res = process_watchfile(@arguments);
    if($found) {
      #...
    }
  }
  

=back

=head1 SEE ALSO

L<uscan(1)>, L<Devscripts::Uscan::WatchFile(3pm)>

=head1 AUTHOR

Xavier Guimard <yadd@debian.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2021 by Xavier Guimard

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.32.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
