# This test launch a test for each directory in t/uscan/. See
# t/uscan/README.md to learn how to write a test

use Test::More;
use Archive::Tar;
use Compress::Zlib;
use File::Find;
use LWP::Protocol::PSGI;
use Plack::Request;
use File::Copy;

use_ok('Devscripts::Uscan');

# Constants
my $archive_ext = Devscripts::Uscan::WatchFile::ARCHIVE_EXT();
$archive_ext = qr/$archive_ext$/;

our $cwd = `pwd`;

# Register fake HTTP server
LWP::Protocol::PSGI->register(\&http_server);

# TESTS (see t/uscan/README.md)

opendir my $dir, 't/uscan';
foreach my $test_dir (sort readdir $dir) {
    next unless $test_dir =~ /^[\w-]+$/;
    next unless -d "t/uscan/$test_dir";
    next if -e "t/uscan/$test_dir/internet" and !$ENV{TEST_INTERNET};
    next unless $test_dir =~ /gitlab/;
    diag "Test: $test_dir";
    chdir "t/uscan/$test_dir" or fail "Unable to chdir to t/uscan/$test_dir";
    my @remove;
    @remove = prepare_testdir() unless ($test_dir eq 'simple_test');
    @ARGV   = ('--no-conf', ($ENV{TEST_USCAN_DEBUG} ? ('-vvv') : ()));

    if (-e 'options') {
        open my $f, '<', 'options';
        while (<$f>) {
            chomp;
            s/\s*(?:#.*)$//;
            s/^\s+//;
            next if /^$/;
            if (/(-\S+)\s+["']?(.+?)["']?$/) {
                push @ARGV, $1, $2;
            } else {
                push @ARGV, $_;
            }
        }
        close $f;
    }
    my ($res, $found) = uscan();

    if (-e 'fail') {
        ok($res, 'uscan failed');
    } else {
        ok($res == 0, 'uscan succeeded');
    }
    subtest 'Check downloaded files', sub {
        my $filesFound = 0;
        if (-e 'wanted_files') {
            open my $f, '<', 'wanted_files';
            while (<$f>) {
                chomp;
                s/#.*$//;
                s/^\s+//;
                s/\s+$//;
                next if /^$/;
                if (s/\s+link//) {
                    ok(-l "../$_", "Link $_ exists");
                } else {
                    ok(-f "../$_", "File $_ exists");
                }
                $filesFound++;
                unlink "../$_";
            }
        }
        opendir my $d, '../';
        map {
            unless ($_ =~ /^\./ or -d "../$_" or /\.md$/) {
                fail "$_ exists and is not declared in wanted_files";
                $filesFound++;
                unlink "../$_";
            }
        } readdir($d);
        pass 'No files downloaded' unless $filesFound;
        closedir $dir;
    };
    clean_testdir(@remove) unless ($test_dir eq 'simple_test');
    chdir('../../..') or fail($!);
}

done_testing();

# FUNCTIONS

sub build_tar {
    my $tar = Archive::Tar->new;
    if (-e 'tar_content') {
        open my $fh, '<', 'tar_content';
        while (<$fh>) {
            chomp;
            s/\s*#.*$//;
            s/^\s*//;
            s/\s*$//;
            next if /^$/;
            $tar->add_data($_, '$_ content');
        }
    } else {
        $tar->add_data('README', 'Readme content');
    }
    my $out = IO::String->new;
    binmode $out;
    $tar->write($out);
    $out->pos(0);
    local $/ = undef;
    my $ret = <$out>;
    close $out;
    return ('application/gzip', Compress::Zlib::memGzip($ret));
}

sub prepare_testdir {
    my $ref = '../simple_test/debian/';
    my @remove;
    my @refs;
    mkdir 'debian';
    find(
        sub {
            push @refs, $File::Find::name unless /watch/;
        },
        '../simple_test/debian'
    );
    foreach my $src (@refs) {
        my $dest = $src;
        $dest =~ s#^../simple_test/##;
        if (!-e $dest) {
            unshift @remove, $dest;
            if (-d $src) {
                mkdir $dest;
            } else {
                copy($src, $dest)
                  or fail "Unable to copy $dest: $!\n" . `pwd`;
            }
        }
    }
    return @remove;
}

sub clean_testdir {
    foreach (@_) {
        if (-d $_) {
            rmdir $_ or fail "Unable to rmdir $_";
        } else {
            unlink $_ or fail "Unable to remove $_";
        }
    }
    rmdir 'debian';
}

# Fake HTTP server

sub http_server {
    my $req  = Plack::Request->new(@_);
    my $file = $req->path_info;
    $file =~ s#/+#_#g;
    if ($file =~ $archive_ext or $file =~ /\d$/) {
        if (-e $file) {
            open my $fh, '<', $file;
            binmode $fh;
            local $/ = undef;
            my $content = <$fh>;
            close $fh;
            return [
                200,
                [
                    'Content-Type'   => 'application/data',
                    'Content-Length' => length($content)
                ],
                [$content]];
        }
        my ($contentType, $content) = build_tar($file);
        return [
            200,
            [
                'Content-Type'   => $contentType,
                'Content-Length' => length($content)
            ],
            [$content]];
    } else {
        $file = "$file.html" if (-e "$file.html");
        return FILE_NOT_FOUND($file) unless -e $file;
        local $/ = undef;
        open my $fh, '<', $file;
        my $content = <$fh>;
        close $fh;
        return [
            200,
            [
                'Content-Length' => length($content),
                'Content-Type'   => 'text/html'
            ],
            [$content]];
    }
}

sub SERVER_ERROR {
    fail join("\n", @_);
    return [500, [], []];
}

sub FILE_NOT_FOUND {
    diag "File not found $_[0]";
    return [404, [], []];
}
