# Copyright (C) 2022, Niels Thykier <niels@thykier.net>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

"""test_control.py - Run unit tests for the Control module"""
import textwrap

try:
    from debian._deb822_repro.formatter import (
        COMMA_SEPARATOR_FT,
        FormatterContentToken,
        format_field,
    )
except ImportError as e:
    print(e)
    COMMA_SEPARATOR = object()
    FormatterContentToken = object()

    def format_field(formatter, field_name, separator_token, token_iter):
        raise AssertionError("Test should have been skipped!")


from devscripts.control import (
    HAS_FULL_RTS_FORMATTING,
    HAS_RTS_PARSER,
    Control,
    wrap_and_sort_formatter,
)
from devscripts.test import unittest


def _dedent(text):
    """Dedent and remove "EOL" line markers

    Removes ¶ which are used as "EOL" markers. The EOL markers helps humans understand
    that there is trailing whitespace (and it is significant) but also stops "helpful"
    editors from pruning it away and thereby ruining the text.
    """
    return textwrap.dedent(text).replace("¶", "")


def _prune_trailing_whitespace(text):
    return "\n".join(x.rstrip() for x in text.splitlines()) + (
        "\n" if text.endswith("\n") else ""
    )


class ControlTestCase(unittest.TestCase):
    @unittest.skipIf(not HAS_RTS_PARSER, "Requires a newer version of python-debian")
    def test_rts_parsing(self):
        orig_content = _dedent(
            """\
            Source: devscripts   ¶
            Maintainer: Jane Doe <jane.doe@debian.org>¶
            # Some comment about Build-Depends:  ¶
            Build-Depends: foo, ¶
            # We need bar (>= 1.2~) because of reason ¶
               bar     (>=1.2~) ¶
            ¶
            Package: devscripts ¶
            Architecture: arm64¶
              linux-any  ¶
            # Some comment describing why hurd-i386 would work while hurd-amd64 did not¶
              hurd-i386¶
            ¶
            # This should be the "last" package after sorting¶
            Package: z-pkg¶
            Architecture: any¶
            ¶
            ¶
            ¶
            # Random comment here¶
            ¶
            ¶
            ¶
            # This should be the second one with -kb and the first with -b¶
            Package: a-pkg¶
            Architecture: any¶
            ¶
            ¶
            """
        )

        # "No change" here being just immediately dumping the content again.  This will
        # only prune empty lines (we do not preserve these in wrap-and-sort).
        no_change_dump_content = _dedent(
            """\
            Source: devscripts   ¶
            Maintainer: Jane Doe <jane.doe@debian.org>¶
            # Some comment about Build-Depends:  ¶
            Build-Depends: foo, ¶
            # We need bar (>= 1.2~) because of reason ¶
               bar     (>=1.2~) ¶
            ¶
            Package: devscripts ¶
            Architecture: arm64¶
              linux-any  ¶
            # Some comment describing why hurd-i386 would work while hurd-amd64 did not¶
              hurd-i386¶
            ¶
            # This should be the "last" package after sorting¶
            Package: z-pkg¶
            Architecture: any¶
            ¶
            # Random comment here¶
            ¶
            # This should be the second one with -kb and the first with -b¶
            Package: a-pkg¶
            Architecture: any¶
            """
        )

        last_paragraph_swap_no_trailing_space = _dedent(
            """\
            Source: devscripts¶
            Maintainer: Jane Doe <jane.doe@debian.org>¶
            # Some comment about Build-Depends:¶
            Build-Depends: foo,¶
            # We need bar (>= 1.2~) because of reason¶
               bar     (>=1.2~)¶
            ¶
            Package: devscripts¶
            Architecture: arm64¶
              linux-any¶
            # Some comment describing why hurd-i386 would work while hurd-amd64 did not¶
              hurd-i386¶
            ¶
            # This should be the second one with -kb and the first with -b¶
            Package: a-pkg¶
            Architecture: any¶
            ¶
            # Random comment here¶
            ¶
            # This should be the "last" package after sorting¶
            Package: z-pkg¶
            Architecture: any¶
            """
        )

        control = Control(
            "debian/control", fd=orig_content.splitlines(True), use_rts_parser=True
        )
        self.assertEqual(control.dump(), no_change_dump_content)

        control.strip_trailing_whitespace_on_save = True
        stripped_space = _prune_trailing_whitespace(no_change_dump_content)
        self.assertNotEqual(stripped_space, no_change_dump_content)
        self.assertEqual(control.dump(), stripped_space)

        control.paragraphs[-2], control.paragraphs[-1] = (
            control.paragraphs[-1],
            control.paragraphs[-2],
        )
        self.assertEqual(control.dump(), last_paragraph_swap_no_trailing_space)

    @unittest.skipIf(
        not HAS_FULL_RTS_FORMATTING, "Requires a newer version of python-debian"
    )
    def test_rts_formatter(self):
        # Note that we skip whitespace and separator tokens because:
        # 1) The underlying formatters ignores them anyway, so they do not affect
        #    the outcome
        # 2) It makes the test easier to understand
        tokens_with_comment = [
            FormatterContentToken.value_token("foo"),
            FormatterContentToken.comment_token("# some comment about bar\n"),
            FormatterContentToken.value_token("bar"),
        ]
        tokens_without_comment = [
            FormatterContentToken.value_token("foo"),
            FormatterContentToken.value_token("bar"),
        ]

        tokens_very_long_content = [
            FormatterContentToken.value_token("foo"),
            FormatterContentToken.value_token("bar"),
            FormatterContentToken.value_token("some-very-long-token"),
            FormatterContentToken.value_token("this-should-trigger-a-wrap"),
            FormatterContentToken.value_token("with line length 20"),
            FormatterContentToken.value_token(
                "and (also) show we do not mash up spaces"
            ),
            FormatterContentToken.value_token("inside value tokens"),
        ]

        tokens_starting_comment = [
            FormatterContentToken.comment_token("# some comment about foo\n"),
            FormatterContentToken.value_token("foo"),
            FormatterContentToken.value_token("bar"),
        ]

        formatter_stl = wrap_and_sort_formatter(
            1,  # -s
            immediate_empty_line=True,  # -s
            trailing_separator=True,  # -t
            max_line_length_one_liner=20,  # --max-line-length
        )
        formatter_sl = wrap_and_sort_formatter(
            1,  # -s
            immediate_empty_line=True,  # -s
            trailing_separator=False,  # No -t
            max_line_length_one_liner=20,  # --max-line-length
        )
        actual = format_field(
            formatter_stl, "Depends", COMMA_SEPARATOR_FT, tokens_without_comment
        )
        # Without comments, format this as one line
        expected = textwrap.dedent(
            """\
            Depends: foo, bar,
            """
        )
        self.assertEqual(actual, expected)

        # With comments, we degenerate into "wrap_always" mode (for simplicity)
        actual = format_field(
            formatter_stl, "Depends", COMMA_SEPARATOR_FT, tokens_with_comment
        )
        expected = textwrap.dedent(
            """\
            Depends:
             foo,
            # some comment about bar
             bar,
            """
        )
        self.assertEqual(actual, expected)

        # Starting with a comment should also work
        actual = format_field(
            formatter_stl, "Depends", COMMA_SEPARATOR_FT, tokens_starting_comment
        )
        expected = textwrap.dedent(
            """\
            Depends:
            # some comment about foo
             foo,
             bar,
            """
        )
        self.assertEqual(actual, expected)

        # Without trailing comma
        actual = format_field(
            formatter_sl, "Depends", COMMA_SEPARATOR_FT, tokens_without_comment
        )
        expected = textwrap.dedent(
            """\
            Depends: foo, bar
            """
        )
        self.assertEqual(actual, expected)

        # Triggering a wrap
        actual = format_field(
            formatter_sl, "Depends", COMMA_SEPARATOR_FT, tokens_very_long_content
        )
        expected = textwrap.dedent(
            """\
            Depends:
             foo,
             bar,
             some-very-long-token,
             this-should-trigger-a-wrap,
             with line length 20,
             and (also) show we do not mash up spaces,
             inside value tokens
            """
        )
        self.assertEqual(actual, expected)
