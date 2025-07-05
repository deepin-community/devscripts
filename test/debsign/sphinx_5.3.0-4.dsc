Format: 3.0 (quilt)
Source: sphinx
Binary: python3-sphinx, sphinx-common, sphinx-doc, libjs-sphinxdoc
Architecture: all
Version: 5.3.0-4
Maintainer: Debian Python Team <team+python@tracker.debian.org>
Uploaders: Dmitry Shachnev <mitya57@debian.org>
Homepage: https://www.sphinx-doc.org/
Standards-Version: 4.6.2
Vcs-Browser: https://salsa.debian.org/python-team/packages/sphinx
Vcs-Git: https://salsa.debian.org/python-team/packages/sphinx.git
Testsuite: autopkgtest
Testsuite-Triggers: dvipng, fonts-freefont-otf, gir1.2-webkit-6.0, graphviz, imagemagick-6.q16, librsvg2-bin, python3-all, python3-gi, python3-html5lib, python3-pytest, python3-setuptools, python3-sphinxcontrib.websupport, python3-sqlalchemy, python3-whoosh, python3-xapian, tex-gyre, texinfo, texlive-fonts-recommended, texlive-latex-extra, texlive-luatex, texlive-xetex, xauth, xvfb
Build-Depends: debhelper-compat (= 13)
Build-Depends-Indep: dh-python (>= 3.20180313~), dpkg-dev (>= 1.17.14), dvipng, flit (>= 3.7), fonts-freefont-otf, graphviz, imagemagick-6.q16, libjs-jquery (>= 1.4), libjs-underscore, libjson-perl <!nodoc>, librsvg2-bin, perl, pybuild-plugin-pyproject, python-requests-doc <!nodoc>, python3-alabaster (>= 0.7), python3-all (>= 3.3.3-1~), python3-babel (>= 1.3), python3-doc <!nodoc>, python3-docutils (>= 0.14), python3-html5lib, python3-imagesize, python3-jinja2 (>= 2.3), python3-lib2to3, python3-packaging, python3-pygments (>= 2.13), python3-pytest, python3-requests (>= 2.5.0), python3-setuptools, python3-snowballstemmer (>= 1.1), python3-sphinxcontrib.websupport <!nodoc>, tex-gyre, texinfo, texlive-fonts-recommended, texlive-latex-extra, texlive-latex-recommended, texlive-luatex, texlive-xetex
Package-List:
 libjs-sphinxdoc deb javascript optional arch=all
 python3-sphinx deb python optional arch=all
 sphinx-common deb python optional arch=all
 sphinx-doc deb doc optional arch=all profile=!nodoc
Checksums-Sha1:
 5f3f8f97b4b8a9f59c8bf2b7b1d2ff294c0a65af 6823676 sphinx_5.3.0.orig.tar.gz
 001d755237dfa5e0c746ff0227b81c2af8a40da1 43816 sphinx_5.3.0-4.debian.tar.xz
Checksums-Sha256:
 27655e5bb08ffc22bf9fbdc1df818da4012ca10a9c37f68f09fd674f03825f43 6823676 sphinx_5.3.0.orig.tar.gz
 d11a31e0516d32ddf11f424eb4b84d3b56565109762c22c51a81e68bd40d6488 43816 sphinx_5.3.0-4.debian.tar.xz
Files:
 752d116a6d4d5dea6c84952869378509 6823676 sphinx_5.3.0.orig.tar.gz
 020c8e9dce1b287ca1a57bcd75af9b6b 43816 sphinx_5.3.0-4.debian.tar.xz
