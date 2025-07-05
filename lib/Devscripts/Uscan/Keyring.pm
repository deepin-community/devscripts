package Devscripts::Uscan::Keyring;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Dpkg::IPC;
use Dpkg::Path qw/find_command/;
use File::Copy qw/copy move/;
use File::Path qw/make_path remove_tree/;
use File::Temp qw/tempfile tempdir/;
use List::Util qw/first/;
use MIME::Base64;

# _pgp_* functions are strictly for applying or removing ASCII armor.
# see https://www.rfc-editor.org/rfc/rfc9580.html#section-6 for more
# details.

# Note that these _pgp_* functions are only necessary while relying on
# gpgv, and gpgv itself does not verify multiple signatures correctly
# (see https://bugs.debian.org/1010955)

sub _pgp_unarmor_data {
    my ($type, $data, $filename) = @_;
    # note that we ignore an incorrect or absent checksum, following the
    # guidance of
    # https://www.rfc-editor.org/rfc/rfc9580.html#section-6.1-3

    my $armor_regex = qr{
                          -----BEGIN\ PGP\ \Q$type\E-----[\r\t ]*\n
                          (?:[^:\n]+:\ [^\n]*[\r\t ]*\n)*
                          [\r\t ]*\n
                          ([a-zA-Z0-9/+\n]+={0,2})[\r\t ]*\n
                          (?:=[a-zA-Z0-9/+]{4}[\r\t ]*\n)?
                          -----END\ PGP\ \Q$type\E-----
                        }xm;

    my $blocks = 0;
    my $binary;
    while ($data =~ m/$armor_regex/g) {
        $binary .= decode_base64($1);
        $blocks++;
    }
    if ($blocks > 1) {
        uscan_warn "Found multiple concatenated ASCII Armor blocks in\n"
          . "  $filename, which is not an interoperable construct.\n"
          . "  See <https://tests.sequoia-pgp.org/results.html#ASCII_Armor>.\n"
          . "  Please concatenate them into a single ASCII Armor block. For example:\n"
          . "    sq keyring merge --overwrite --output $filename \\\n"
          . "      $filename";
    }
    return $binary;
}

sub _pgp_armor_checksum {
    my ($data) = @_;
    # from https://www.rfc-editor.org/rfc/rfc9580.html#section-6.1.1
    #
    # #define CRC24_INIT 0xB704CEL
    # #define CRC24_GENERATOR 0x864CFBL

    # typedef unsigned long crc24;
    # crc24 crc_octets(unsigned char *octets, size_t len)
    # {
    #     crc24 crc = CRC24_INIT;
    #     int i;
    #     while (len--) {
    #         crc ^= (*octets++) << 16;
    #         for (i = 0; i < 8; i++) {
    #             crc <<= 1;
    #             if (crc & 0x1000000) {
    #                 crc &= 0xffffff; /* Clear bit 25 to avoid overflow */
    #                 crc ^= CRC24_GENERATOR;
    #             }
    #         }
    #     }
    #     return crc & 0xFFFFFFL;
    # }
    #
    # the resulting three-octet-wide value then gets base64-encoded into
    # four base64 ASCII characters.

    my $CRC24_INIT      = 0xB704CE;
    my $CRC24_GENERATOR = 0x864CFB;

    my @bytes = unpack 'C*', $data;
    my $crc   = $CRC24_INIT;
    for my $b (@bytes) {
        $crc ^= ($b << 16);
        for (1 .. 8) {
            $crc <<= 1;
            if ($crc & 0x1000000) {
                $crc &= 0xffffff;    # Clear bit 25 to avoid overflow
                $crc ^= $CRC24_GENERATOR;
            }
        }
    }
    my $sum
      = pack('CCC', (($crc >> 16) & 0xff, ($crc >> 8) & 0xff, $crc & 0xff));
    return encode_base64($sum, q{});
}

sub _pgp_armor_data {
    my ($type, $data) = @_;
    my $out = encode_base64($data, q{}) =~ s/(.{1,64})/$1\n/gr;
    chomp $out;
    my $crc   = _pgp_armor_checksum($data);
    my $armor = <<~"ARMOR";
    -----BEGIN PGP $type-----

    $out
    =$crc
    -----END PGP $type-----
    ARMOR
    return $armor;
}

sub new {
    my ($class) = @_;
    my $keyring;
    my $havegpgv = first { find_command($_) } qw(gpgv);
    my $havesopv = first { find_command($_) } qw(sopv);
    my $havesop
      = first { find_command($_) } qw(sqop rsop pgpainless-cli gosop);
    uscan_die("Please install a sopv variant.")
      unless (defined $havegpgv or defined $havesopv);

    # upstream/signing-key.pgp and upstream-signing-key.pgp are deprecated
    # but supported
    if (-r "debian/upstream/signing-key.asc") {
        $keyring = "debian/upstream/signing-key.asc";
    } else {
        my $binkeyring = first { -r $_ } qw(
          debian/upstream/signing-key.pgp
          debian/upstream-signing-key.pgp
        );
        if (defined $binkeyring) {
            make_path('debian/upstream', { mode => 0700, verbose => 'true' });

            # convert to the policy complying armored key
            uscan_verbose(
                "Found upstream binary signing keyring: $binkeyring");

            # Need to convert to an armored key
            $keyring = "debian/upstream/signing-key.asc";
            uscan_warn "Found deprecated binary keyring ($binkeyring). "
              . "Please save it in armored format in $keyring. For example:\n"
              . "   sop armor < $binkeyring > $keyring";
            if ($havesop) {
                spawn(
                    exec       => [$havesop, 'armor'],
                    from_file  => $binkeyring,
                    to_file    => $keyring,
                    wait_child => 1,
                );
            } else {
                open my $inkeyring, '<', $binkeyring
                  or uscan_warn(
                    "Can't open $binkeyring to read deprecated binary keyring"
                  );
                read $inkeyring, my $keycontent, -s $inkeyring;
                close $inkeyring;
                open my $outkeyring, '>', $keyring
                  or uscan_warn(
                    "Can't open $keyring for writing ASCII-armored keyring");
                my $outkey = _pgp_armor_data('PUBLIC KEY BLOCK', $keycontent);
                print $outkeyring $outkey
                  or
                  uscan_warn("Can't write ASCII-armored keyring to $keyring");
                close $outkeyring or uscan_warn("Failed to close $keyring");
            }

            uscan_warn("Generated upstream signing keyring: $keyring");
            move $binkeyring, "$binkeyring.backup";
            uscan_verbose(
                "Renamed upstream binary signing keyring: $binkeyring.backup");
        }
    }

    # Need to convert an armored key to binary for use by gpgv
    if (defined $keyring) {
        uscan_verbose("Found upstream signing keyring: $keyring");
        if ($keyring =~ m/\.asc$/ && !defined $havesopv)
        {    # binary keyring is only necessary for gpgv:
            my $pgpworkdir = tempdir(CLEANUP => 1);
            my $newkeyring = "$pgpworkdir/upstream-signing-key.pgp";
            open my $inkeyring, '<', $keyring
              or uscan_die("Can't open keyring file $keyring");
            read $inkeyring, my $keycontent, -s $inkeyring;
            close $inkeyring;
            my $binkey
              = _pgp_unarmor_data('PUBLIC KEY BLOCK', $keycontent, $keyring);
            if ($binkey) {
                open my $outkeyring, '>:raw', $newkeyring
                  or uscan_die("Can't write to temporary keyring $newkeyring");
                print $outkeyring $binkey
                  or uscan_die("Can't write $newkeyring");
                close $outkeyring or uscan_die("Can't close $newkeyring");
                $keyring = $newkeyring;
            } else {
                uscan_die("Failed to dearmor key(s) from $keyring");
            }
        }
    }

    # Return undef if not key found
    else {
        return undef;
    }
    my $self = bless {
        keyring => $keyring,
        gpgv    => $havegpgv,
        sopv    => $havesopv,
    }, $class;
    return $self;
}

sub verify {
    my ($self, $sigfile, $newfile) = @_;
    uscan_verbose(
        "Verifying OpenPGP self signature of $newfile and extract $sigfile");
    if ($self->{sopv}) {
        spawn(
            exec       => [$self->{sopv}, 'inline-verify', $self->{keyring}],
            from_file  => $newfile,
            to_file    => $sigfile,
            wait_child => 1
        ) or uscan_die("OpenPGP signature did not verify.");
    } else {
        unless (
            uscan_exec_no_fail(
                $self->{gpgv},
                '--homedir' => '/dev/null',
                '--keyring' => $self->{keyring},
                '-o'        => "$sigfile",
                "$newfile"
            ) >> 8 == 0
        ) {
            uscan_die("OpenPGP signature did not verify.");
        }
    }
}

sub verifyv {
    my ($self, $sigfile, $base) = @_;
    uscan_verbose("Verifying OpenPGP signature $sigfile for $base");
    if ($self->{sopv}) {
        spawn(
            exec      => [$self->{sopv}, 'verify', $sigfile, $self->{keyring}],
            from_file => $base,
            wait_child => 1
        ) or uscan_die("OpenPGP signature did not verify.");
    } else {
        unless (
            uscan_exec_no_fail(
                $self->{gpgv},
                '--homedir' => '/dev/null',
                '--keyring' => $self->{keyring},
                $sigfile, $base
            ) >> 8 == 0
        ) {
            uscan_die("OpenPGP signature did not verify.");
        }
    }
}

sub verify_git {
    my ($self, $gitdir, $tag, $git_upstream) = @_;
    my $commit;
    my @dir = $git_upstream ? () : ('--git-dir', $gitdir);
    spawn(
        exec      => ['git', @dir, 'show-ref', $tag],
        to_string => \$commit
    );
    uscan_die "git tag not found" unless ($commit);
    $commit =~ s/\s.*$//;
    chomp $commit;
    my $file;
    spawn(
        exec      => ['git', @dir, 'cat-file', '-p', $commit],
        to_string => \$file
    );
    my $dir;
    spawn(exec => ['mktemp', '-d'], to_string => \$dir);
    chomp $dir;

    unless ($file =~ /^(.*?\n)(\-+\s*BEGIN PGP SIGNATURE\s*\-+.*)$/s) {
        uscan_die "Tag $tag is not signed";
    }
    open F, ">$dir/txt" or die $!;
    open S, ">$dir/sig" or die $!;
    print F $1;
    print S $2;
    close F;
    close S;

    if ($self->{sopv}) {
        spawn(
            exec => [$self->{sopv}, 'verify', "$dir/sig", $self->{keyring}],
            from_file  => "$dir/txt",
            wait_child => 1
        ) or uscan_die("OpenPGP signature did not verify");
    } else {
        unless (
            uscan_exec_no_fail(
                $self->{gpgv},
                '--homedir' => '/dev/null',
                '--keyring' => $self->{keyring},
                "$dir/sig", "$dir/txt"
            ) >> 8 == 0
        ) {
            uscan_die("OpenPGP signature did not verify.");
        }
    }
    remove_tree($dir);
}

1;
