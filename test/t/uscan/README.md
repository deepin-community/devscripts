# Uscan tests

Each test is a directory here.

Test directory contains:

 * a debian directory containing files to override template files.
   Templates file are in [simple\_test/debian](./simple_test/debian) directory.
 * some files to check result:
   * `fail`: if exists, uscan should fail
   * HTML response files _(see below)_
   * `tar_content`: see [HTML response files](#html-response-files)
   * `wanted_files`: a file that contains the list of files that uscan should
     have downloaded after test. Each file not declared here will produce an
     error. If file has to be a symlink, add ` link` after its name. Example:
     ```
     foo-2.0.0.tar.gz
     foo_2.0.0.orig.tar.gz   link
     ```
   * `options`: add here additional command-line options to give to uscan. One
     option perl line with its optional argument. Example:
     ```
     --download-version 1.0.0
     --repack
     ```

## HTML response files

When `uscan` launches a request, test HTTP server:

 * transforms the path\_info replacing all **`/`** by **`_`**
 * try to find a corresponding file in test directory. It tries also adding
   `.html` except for archive files _(*.tar.gz,...)_. Example:
   * `/` corresponds to `_` or `_.html`
   * `/a/b` corresponds to `_a_b` or `_a_b.html`
 * when file is missing:
   * if filename ends with a archive suffix _(*.tar.gz,...)_, test HTTP server
     builds automatically the archive. Content:
     * if `tar_content` exists, files with corresponding names are added
     * else, archive contains only a `README` file
   * else test HTTP server displays missing filename _(use `prove --verbose` to see it)_
     and returns a 404 response
