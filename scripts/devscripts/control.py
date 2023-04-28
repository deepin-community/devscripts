# control.py - Represents a debian/control file
#
# Copyright (C) 2010, Benjamin Drung <bdrung@debian.org>
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

"""This module implements facilities to deal with Debian control."""
import contextlib
import os
import sys

from devscripts.logger import Logger

try:
    import debian.deb822
except ImportError:
    Logger.error("Please install 'python3-debian' in order to use this utility.")
    sys.exit(1)

try:
    from debian._deb822_repro import Deb822ParagraphElement, parse_deb822_file
    from debian._deb822_repro.tokens import Deb822Token

    HAS_RTS_PARSER = True
except ImportError:
    HAS_RTS_PARSER = False

try:
    from debian._deb822_repro.formatter import one_value_per_line_formatter

    HAS_FULL_RTS_FORMATTING = True
except ImportError:

    def one_value_per_line_formatter(
        indentation, trailing_separator=True, immediate_empty_line=False
    ):
        raise AssertionError(
            "Bug: The dummy one_value_per_line_formatter method should not be called!"
        )

    HAS_FULL_RTS_FORMATTING = False


def _emit_one_line_value(value_tokens, sep_token, trailing_separator):
    first_token = True
    yield " "
    for token in value_tokens:
        if not first_token:
            yield sep_token
            if not sep_token.is_whitespace:
                yield " "
        first_token = False
        yield token
    if trailing_separator and not sep_token.is_whitespace:
        yield sep_token
    yield "\n"


def wrap_and_sort_formatter(
    indentation,
    trailing_separator=True,
    immediate_empty_line=False,
    max_line_length_one_liner=0,
):
    """Provide a formatter that can handle indentation and trailing separators

    This is a custom wrap-and-sort formatter capable of supporting wrap-and-sort's
    needs. Where possible it delegates to python-debian's own formatter.

    :param indentation: Either the literal string "FIELD_NAME_LENGTH" or a positive
    integer, which determines the indentation fields.  If it is an integer,
    then a fixed indentation is used (notably the value 1 ensures the shortest
    possible indentation).  Otherwise, if it is "FIELD_NAME_LENGTH", then the
    indentation is set such that it aligns the values based on the field name.
    This parameter only affects values placed on the second line or later lines.
    :param trailing_separator: If True, then the last value will have a trailing
    separator token (e.g., ",") after it.
    :param immediate_empty_line: Whether the value should always start with an
    empty line.  If True, then the result becomes something like "Field:\n value".
    This parameter only applies to the values that will be formatted over more than
    one line.
    :param max_line_length_one_liner: If greater than zero, then this is the max length
    of the value if it is crammed into a "one-liner" value.  If the value(s) fit into
    one line, this parameter will overrule immediate_empty_line.

    """
    if not HAS_FULL_RTS_FORMATTING:
        raise NotImplementedError(
            "wrap_and_sort_formatter requires python-debian 0.1.44"
        )
    if indentation != "FIELD_NAME_LENGTH" and indentation < 1:
        raise ValueError('indentation must be at least 1 (or "FIELD_NAME_LENGTH")')

    # The python-debian library provides support for all cases except cramming
    # everything into a single line.  So we "only" have to implement the single-line
    # case(s) ourselves (which sadly takes plenty of code on its own)

    _chain_formatter = one_value_per_line_formatter(
        indentation,
        trailing_separator=trailing_separator,
        immediate_empty_line=immediate_empty_line,
    )

    if max_line_length_one_liner < 1:
        return _chain_formatter

    def _formatter(name, sep_token, formatter_tokens):
        # We should have unconditionally delegated to the python-debian formatter
        # if max_line_length_one_liner was set to "wrap_always"
        assert max_line_length_one_liner > 0
        all_tokens = list(formatter_tokens)
        values_and_comments = [x for x in all_tokens if x.is_comment or x.is_value]
        # There are special-cases where you could do a one-liner with comments, but
        # they are probably a lot more effort than it is worth investing.
        # - If you are here because you disagree, patches welcome. :)
        if all(x.is_value for x in values_and_comments):
            # We use " " (1 char) or ", " (2 chars) as separated depending on the field.
            # (at the time of writing, wrap-and-sort only uses this formatted for
            # dependency fields meaning this will be "2" - but now it is future proof).
            chars_between_values = 1 + (0 if sep_token.is_whitespace else 1)
            # Compute the total line length of the field as the sum of all values
            total_len = sum(len(x.text) for x in values_and_comments)
            # ... plus the separators
            total_len += (len(values_and_comments) - 1) * chars_between_values
            # plus the field name + the ": " after the field name
            total_len += len(name) + 2
            if total_len <= max_line_length_one_liner:
                yield from _emit_one_line_value(
                    values_and_comments, sep_token, trailing_separator
                )
                return
            # If it does not fit in one line, we fall through
        # Chain into the python-debian provided formatter, which will handle this
        # formatting for us.
        yield from _chain_formatter(name, sep_token, all_tokens)

    return _formatter


def _insert_after(paragraph, item_before, new_item, new_value):
    """Insert new_item into directly after item_before

    New items added to a dictionary are appended."""
    try:
        paragraph.order_after
    except AttributeError:
        pass
    else:
        # Use order_after from python-debian (>= 0.1.42~), which is O(1) performance
        paragraph[new_item] = new_value
        try:
            paragraph.order_after(new_item, item_before)
        except KeyError:
            # Happens if `item_before` is not present.  We ignore this error because we
            # are fine with `new_item` ending the "end" of the paragraph in that case.
            pass
        return
    # Old method - O(n) performance
    item_found = False
    for item in paragraph:
        if item_found:
            value = paragraph.pop(item)
            paragraph[item] = value
        if item == item_before:
            item_found = True
            paragraph[new_item] = new_value
    if not item_found:
        paragraph[new_item] = new_value


@contextlib.contextmanager
def _open(filename, fd=None, encoding="utf-8", **kwargs):
    if fd is None:
        with open(filename, encoding=encoding, **kwargs) as fileobj:
            yield fileobj
    else:
        yield fd


class Control:
    """Represents a debian/control file"""

    def __init__(self, filename, fd=None, use_rts_parser=None):
        assert fd is not None or os.path.isfile(filename), f"{filename} does not exist."
        self.filename = filename
        self._is_roundtrip_safe = use_rts_parser
        self.strip_trailing_whitespace_on_save = False

        if self._is_roundtrip_safe:
            # Note: wrap-and-sort does not trigger this code path without python-debian
            # 0.1.44 due to the lack of formatter support (that we are not willing to
            # re-implement ourselves). However, the 0.1.43 version is correct for the
            # Control class itself and is left as-is for non-"wrap-and-sort" consumers
            # (if any)
            if not HAS_RTS_PARSER:
                raise ValueError(
                    "The use_rts_parser option requires python-debian 0.1.43 or later"
                )
            with _open(filename, fd=fd, encoding="utf8") as sequence:
                self._deb822_file = parse_deb822_file(sequence)
            self.paragraphs = list(self._deb822_file)
        else:
            self._deb822_file = None
            self.paragraphs = []
            with _open(filename, fd=fd, encoding="utf8") as sequence:
                for paragraph in debian.deb822.Deb822.iter_paragraphs(sequence):
                    self.paragraphs.append(paragraph)

    @property
    def is_roundtrip_safe(self):
        return self._is_roundtrip_safe

    def get_maintainer(self):
        """Returns the value of the Maintainer field."""
        return self.paragraphs[0].get("Maintainer")

    def get_original_maintainer(self):
        """Returns the value of the XSBC-Original-Maintainer field."""
        return self.paragraphs[0].get("XSBC-Original-Maintainer")

    def dump(self):
        if self.is_roundtrip_safe:
            content = self._dump_rts_file()
        else:
            content = "\n".join(x.dump() for x in self.paragraphs)
        if self.strip_trailing_whitespace_on_save:
            content = "\n".join(x.rstrip() for x in content.splitlines()) + "\n"
        return content

    def _dump_rts_file(self):
        # Use a custom dump of the RTS parser in order to:
        # 1) support sorting of paragraphs
        # 2) normalize whitespace between paragraphs
        #
        # Ideally, there would be a simpler way to do this - but for now, this is
        # the best the RTS parser can offer.  (Without the above constraints, we
        # could just have used `self._deb822_file.dump()`)
        paragraph_index = 0
        new_content = ""
        pending_newline = False
        for part in self._deb822_file.iter_parts():
            if isinstance(part, Deb822ParagraphElement):
                part_content = self.paragraphs[paragraph_index].dump()
                paragraph_index += 1
            elif isinstance(part, Deb822Token) and part.is_whitespace:
                # Normalize empty lines between paragraphs to a single newline.
                #
                # Note we do this unconditionally of
                # strip_trailing_whitespace_on_save because preserving whitespace
                # between paragraphs while reordering them produce funky results.
                pending_newline = True
                continue
            else:
                part_content = part.convert_to_text()
            if pending_newline:
                new_content += "\n"
            new_content += part_content
        return new_content

    def save(self, filename=None):
        """Saves the control file."""
        if filename:
            self.filename = filename
        content = self.dump()
        with open(self.filename, "wb") as control_file:
            control_file.write(content.encode("utf-8"))

    def set_maintainer(self, maintainer):
        """Sets the value of the Maintainer field."""
        self.paragraphs[0]["Maintainer"] = maintainer

    def set_original_maintainer(self, original_maintainer):
        """Sets the value of the XSBC-Original-Maintainer field."""
        if "XSBC-Original-Maintainer" in self.paragraphs[0]:
            self.paragraphs[0]["XSBC-Original-Maintainer"] = original_maintainer
        else:
            _insert_after(
                self.paragraphs[0],
                "Maintainer",
                "XSBC-Original-Maintainer",
                original_maintainer,
            )
