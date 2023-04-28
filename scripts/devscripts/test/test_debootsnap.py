# Copyright (C) 2023, Benjamin Drung <bdrung@debian.org>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

"""Test debootsnap script."""

import contextlib
import io
import tempfile
import unittest
import unittest.mock

from debootsnap import main, parse_pkgs


class TestDebootsnap(unittest.TestCase):
    """Test debootsnap script."""

    @unittest.mock.patch("shutil.which")
    def test_missing_tools(self, which_mock) -> None:
        """Test debootsnap fails cleanly if required binaries are missing."""
        which_mock.return_value = None
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaisesRegex(SystemExit, "1"):
                main(["--packages=pkg1:arch=ver1", "chroot.tar"])
        self.assertEqual(
            stderr.getvalue(), "equivs-build is required but not installed\n"
        )
        which_mock.assert_called_once_with("equivs-build")

    def test_parse_pkgs_from_file(self) -> None:
        """Test parse_pkgs() for a given file name."""
        with tempfile.NamedTemporaryFile(mode="w", prefix="devscripts-") as pkgfile:
            pkgfile.write("pkg1:arch=ver1\npkg2:arch=ver2\n")
            pkgfile.flush()
            pkgs = parse_pkgs(pkgfile.name)
        self.assertEqual(pkgs, [[("pkg1", "arch", "ver1"), ("pkg2", "arch", "ver2")]])

    def test_parse_pkgs_missing_file(self) -> None:
        """Test parse_pkgs() for a missing file name."""
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaisesRegex(SystemExit, "1"):
                parse_pkgs("/non-existing/pkgfile")
        self.assertEqual(stderr.getvalue(), "/non-existing/pkgfile does not exist\n")
