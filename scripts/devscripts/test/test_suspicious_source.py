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

"""Test suspicious-source script."""

import pathlib
import subprocess
import tempfile
import unittest


class TestSuspiciousSource(unittest.TestCase):
    """Test suspicious-source script."""

    @staticmethod
    def _run_suspicious_source(directory: str) -> str:
        suspicious_source = subprocess.run(
            ["./suspicious-source", "-d", directory],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        )
        return suspicious_source.stdout.strip()

    def test_python_sript(self) -> None:
        """Test not complaining about Python code."""
        with tempfile.TemporaryDirectory(prefix="devscripts-") as tmpdir:
            python_file = pathlib.Path(tmpdir) / "example.py"
            python_file.write_text("#!/usr/bin/python3\nprint('hello world')\n")
            self.assertEqual(self._run_suspicious_source(tmpdir), "")
