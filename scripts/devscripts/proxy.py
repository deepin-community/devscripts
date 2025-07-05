# SPDX-FileCopyrightText: 2024 Johannes Schauer Marin Rodrigues <josch@debian.org>
# SPDX-License-Identifier: MIT

import http.server
import logging
import os
import pathlib
import shutil
import tempfile
import threading
import urllib
from functools import partial
from http import HTTPStatus


# we use a http proxy for two reasons
#  1. it allows us to cache package data locally which is useful even for
#     single runs because temporally close snapshot timestamps share packages
#     and thus we reduce the load on snapshot.d.o which is also useful because
#  2. snapshot.d.o requires manual bandwidth throttling or else it will cut
#     our TCP connection. Instead of using Acquire::http::Dl-Limit as an apt
#     option we use a proxy to only throttle on the initial download and then
#     serve the data with full speed once we have it locally
#
# We use SimpleHTTPRequestHandler over BaseHTTPRequestHandler for its directory
# member. We disable its other features, namely do_HEAD
class Proxy(http.server.SimpleHTTPRequestHandler):
    def do_HEAD(self):
        raise NotImplementedError

    # no idea how to split this function into parts without making it
    # unreadable
    def do_GET(self):
        assert int(self.headers.get("Content-Length", 0)) == 0
        assert self.headers["Host"]
        pathprefix = "http://" + self.headers["Host"] + "/"
        assert self.path.startswith(pathprefix)
        sanitizedpath = urllib.parse.unquote(self.path.removeprefix(pathprefix))

        # check validity and extract the timestamp
        try:
            chunk1, chunk2, timestamp, _ = sanitizedpath.split("/", 3)
        except ValueError:
            logging.error("don't know how to handle this request: %s", self.path)
            self.send_error(HTTPStatus.BAD_REQUEST, f"Bad request path ({self.path})")
            return
        if ["archive", "debian"] != [chunk1, chunk2]:
            logging.error("don't know how to handle this request: %s", self.path)
            self.send_error(HTTPStatus.BAD_REQUEST, f"Bad request path ({self.path})")
            return
        # make sure the pool directory is symlinked to the global pool
        linkname = os.path.join(self.directory, chunk1, chunk2, timestamp, "pool")
        if not os.path.exists(linkname):
            os.makedirs(
                os.path.join(self.directory, chunk1, chunk2, timestamp), exist_ok=True
            )
            try:
                os.symlink("../../../pool", linkname)
            except FileExistsError:
                pass

        cachedir = pathlib.Path(self.directory)
        path = cachedir / sanitizedpath

        # just send back to client
        if path.exists() and path.stat().st_size > 0:
            self.wfile.write(b"HTTP/1.1 200 OK\r\n")
            self.send_header("Content-Length", path.stat().st_size)
            self.end_headers()
            with path.open(mode="rb") as new:
                while True:
                    buf = new.read(64 * 1024)  # same as shutil uses
                    if not buf:
                        break
                    self.wfile.write(buf)
            self.wfile.flush()
            return

        self.do_download(path)

    # pylint: disable=too-many-branches,too-many-statements
    def do_download(self, path):
        # download fresh copy
        todownload = downloaded_bytes = 0
        partial_size = None
        # The PID is part of the name of the temporary file. That way, multiple
        # concurrent processes can write out partial files without conflicting
        # with each other and while still maintaining reproducible paths
        # between individual calls of do_download() by the same process.
        tmppath = path.with_suffix(f".{os.getpid()}.part")
        if self.headers.get("Range"):
            assert tmppath.is_file()
            assert self.headers["Range"].startswith("bytes=")
            assert self.headers["Range"].endswith("-")
            reqrange = int(
                self.headers["Range"].removeprefix("bytes=").removesuffix("-")
            )
            assert reqrange <= tmppath.stat().st_size
            partial_size = reqrange
        else:
            tmppath.parent.mkdir(parents=True, exist_ok=True)
        conn = http.client.HTTPConnection(self.headers["Host"], timeout=30)
        conn.request("GET", self.path, None, dict(self.headers))
        try:
            res = conn.getresponse()
        except TimeoutError:
            try:
                self.send_error(504)  # Gateway Timeout
            except BrokenPipeError:
                pass
            return
        if res.status == 302:
            # clean up connection so it can be reused for the 302 redirect
            res.read()
            res.close()
            newpath = res.getheader("Location")
            assert newpath.startswith("/file/"), newpath
            conn.request("GET", newpath, None, dict(self.headers))
            try:
                res = conn.getresponse()
            except TimeoutError:
                try:
                    self.send_error(504)  # Gateway Timeout
                except BrokenPipeError:
                    pass
                return
        if partial_size is not None:
            if res.status != 206:
                try:
                    self.send_error(res.status)
                except BrokenPipeError:
                    pass
                return
            self.wfile.write(b"HTTP/1.1 206 Partial Content\r\n")
            logging.info("proxy: resuming download from byte %d", partial_size)
        else:
            if res.status != 200:
                try:
                    self.send_error(res.status)
                except BrokenPipeError:
                    pass
                return
            self.wfile.write(b"HTTP/1.1 200 OK\r\n")
        todownload = int(res.getheader("Content-Length"))
        for key, value in res.getheaders():
            # do not allow a persistent connection
            if key == "connection":
                continue
            self.send_header(key, value)
        self.end_headers()
        if partial_size is not None:
            total_size = todownload + partial_size
            assert (
                res.getheader("Content-Range")
                == f"bytes {partial_size}-{total_size - 1}/{total_size}"
            ), (
                res.getheader("Content-Range"),
                f"bytes {partial_size}-{total_size - 1}/{total_size}",
            )
        downloaded_bytes = 0
        with tmppath.open(mode="ab") as file:
            if partial_size is not None and file.tell() != partial_size:
                file.seek(partial_size, os.SEEK_SET)
            # we are not using shutil.copyfileobj() because we want to
            # write to two file objects simultaneously and throttle the
            # writing speed to 1024 kB/s
            while True:
                buf = res.read(64 * 1024)  # same as shutil uses
                if not buf:
                    break
                downloaded_bytes += len(buf)
                try:
                    self.wfile.write(buf)
                except BrokenPipeError:
                    break
                file.write(buf)
                # now that snapshot.d.o is fixed, we do not need to throttle
                # the download speed anymore
                # sleep(0.5)  # 128 kB/s
        self.wfile.flush()
        if todownload == downloaded_bytes and downloaded_bytes > 0:
            tmppath.rename(path)

    # pylint: disable=redefined-builtin
    def log_message(self, format, *args):
        pass


def setupcache(cache, port):
    if cache:
        cachedir = cache
        for path in pathlib.Path(cachedir).glob("**/*.part"):
            # we are not deleting *.part files so that multiple processes can
            # use the cache at the same time without having their *.part files
            # deleted by another process
            logging.warning(
                "found partial file in cache, consider deleting it manually: %s", path
            )
    else:
        cachedir = tempfile.mkdtemp(prefix="debbisect")
    logging.info("using cache directory: %s", cachedir)
    os.makedirs(cachedir + "/pool", exist_ok=True)

    # we are not using a ThreadedHTTPServer because
    #  - additional complexity needed if one download created a .part file
    #    then apt stops reading while we still try to read from snapshot and
    #    apt retries the same download trying to write to the same .part file
    #    opened in another threat
    #  - snapshot.d.o really doesn't like fast downloads, so we do it serially
    httpd = http.server.HTTPServer(
        server_address=("127.0.0.1", port),
        RequestHandlerClass=partial(Proxy, directory=cachedir),
    )
    # run server in a new thread
    server_thread = threading.Thread(target=httpd.serve_forever)
    server_thread.daemon = True
    # start thread
    server_thread.start()
    # retrieve port (in case it was generated automatically)
    _, port = httpd.server_address

    def teardown():
        httpd.shutdown()
        httpd.server_close()
        server_thread.join()
        if not cache:
            # this should be a temporary directory but lets still be super
            # careful
            if os.path.exists(cachedir + "/pool"):
                shutil.rmtree(cachedir + "/pool")
            if os.path.exists(cachedir + "/archive"):
                shutil.rmtree(cachedir + "/archive")
            os.rmdir(cachedir)

    return port, teardown
