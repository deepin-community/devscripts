#!/usr/bin/python3

import pathlib
import re

from setuptools import setup

from devscripts.test import SCRIPTS


def get_debian_version() -> str:
    """Determine the Debian package version from debian/changelog."""
    changelog = pathlib.Path(__file__).parent.parent / "debian" / "changelog"
    with changelog.open(encoding="utf8") as f:
        head = f.readline()
    match = re.match(r".*\((.*)\).*", head)
    assert match, f"Failed to extract version from '{head}'."
    return match.group(1)


def make_pep440_compliant(version: str) -> str:
    """Convert the version into a PEP440 compliant version."""
    public_version_re = re.compile(
        r"^([0-9][0-9.]*(?:(?:a|b|rc|.post|.dev)[0-9]+)*)\+?"
    )
    _, public, local = public_version_re.split(version, maxsplit=1)
    if not local:
        return version
    sanitized_local = re.sub("[+~]+", ".", local).strip(".")
    pep440_version = f"{public}+{sanitized_local}"
    assert re.match(
        "^[a-zA-Z0-9.]+$", sanitized_local
    ), f"'{pep440_version}' not PEP440 compliant"
    return pep440_version


def write_version(version: str) -> None:
    """Write version into devscripts/__init__.py."""
    init_py = pathlib.Path(__file__).parent / "devscripts" / "__init__.py"
    init_py.write_text(f'__version__ = "{version}"\n', encoding="utf-8")


if __name__ == "__main__":
    VERSION = make_pep440_compliant(get_debian_version())
    write_version(VERSION)
    setup(
        name="devscripts",
        version=VERSION,
        scripts=SCRIPTS,
        packages=["devscripts"],
        test_suite="devscripts.test",
    )
