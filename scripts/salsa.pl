#!/usr/bin/perl

=head1 NAME

salsa - tool to manipulate salsa projects, repositories and group members

=head1 SYNOPSIS

  # salsa <command> <parameters> <options>
  salsa add_user developer foobar --group-id 2665
  salsa delete_user foobar --group js-team
  salsa search_groups perl-team/modules
  salsa search_projects qa/qa
  salsa search_users yadd
  salsa update_user maintainer foobar --group js-team
  salsa whoami
  salsa checkout node-mongodb --group js-team
  salsa fork salsa fork --group js-team user/node-foo
  salsa last_ci_status js-team/nodejs
  salsa pipelines js-team/nodejs
  salsa mr debian/foo debian/master
  salsa push_repo . --group js-team --kgb --irc devscripts --tagpending
  salsa update_projects node-mongodb --group js-team --disable-kgb --desc \
        --desc-pattern "Package %p"
  salsa update_safe --all --desc --desc-pattern "Debian package %p" \
        --group js-team

=head1 DESCRIPTION

B<salsa> is designed to create and configure projects and repositories on
L<https://salsa.debian.org> as well as to manage group members.

A Salsa token is required, except for search* commands, and must be set in
command line I<(see below)>, or in your configuration file I<(~/.devscripts)>:

  SALSA_TOKEN=abcdefghi

or

  SALSA_TOKEN=`cat ~/.token`

or

  SALSA_TOKEN_FILE=~/.dpt.conf

If you choose to link another file using SALSA_TOKEN_FILE, it must contain a
line with one of (no differences):

  <anything>SALSA_PRIVATE_TOKEN=xxxx
  <anything>SALSA_TOKEN=xxxx

This allows for example to use dpt(1) configuration file (~/.dpt.conf) which
contains:

  DPT_SALSA_PRIVATE_TOKEN=abcdefghi

=head1 COMMANDS

=head2 Managing users and groups

=over

=item B<add_user>

Add a user to a group.

  salsa --group js-group add_user guest foouser
  salsa --group-id 1234 add_user guest foouser
  salsa --group-id 1234 add_user maintainer 1245

First argument is the GitLab's access levels: guest, reporter, developer,
maintainer, owner.

=item B<delete_user> or B<del_user>

Remove a user from a group.

  salsa --group js-team delete_user foouser
  salsa --group-id=1234 delete_user foouser

=item B<join>

Request access to a group.

  salsa join js-team
  salsa join --group js-team
  salsa join --group-id 1234

=item B<list_groups>

List the subgroups for current group if group is set, otherwise
will do the current user.

=item B<list_users> or B<group>

List users in a subgroup.
Note, this does not include inherited or invited.

  salsa --group js-team list_users
  salsa --group-id 1234 list_users

=item B<search_groups>

Search for a group using given string. Shows group ID and other
information.

  salsa search_groups perl-team
  salsa search_groups perl-team/modules
  salsa search_groups 2666

=item B<search_users>

Search for a user using given string. Shows user ID and other information.

  salsa search_users yadd

=item B<update_user>

Update a user's role in a group.

  salsa --group-id 1234 update_user guest foouser
  salsa --group js-team update_user maintainer 1245

First argument is the GitLab's access levels: guest, reporter, developer,
maintainer, owner.

=item B<whoami>

Gives information on the token owner.

  salsa whoami

=back

=head2 Managing projects

One of C<--group>, C<--group-id>, C<--user> or C<--user-id> is required to
manage projects. If both are set, salsa warns and only
C<--user>/C<--user-id> is used. If none is given, salsa uses current user ID
I<(token owner)>.

=over

=item B<check_projects> or B<check_repo>

Verify that projects are configured as expected. It works exactly like B<update_projects>
except that it does not modify anything but just lists projects not well
configured with found errors.

  salsa --user yadd --tagpending --kgb --irc=devscripts check_projects test
  salsa --group js-team check_projects --all
  salsa --group js-team --rename-head check_projects test1 test2 test3

=item B<checkout> or B<co>

Clone a project's repository in current directory. If the directory already
exists, update local repository.

  salsa --user yadd checkout devscripts
  salsa --group js-team checkout node-mongodb
  salsa checkout js-team/node-mongodb

You can clone more than one repository or all repositories of a group or a
user:

  salsa --user yadd checkout devscripts autodep8
  salsa checkout yadd/devscripts js-team/npm
  salsa --group js-team checkout --all           # All js-team active repositories
  salsa checkout --all-archived                  # All your repositories, including archived

=item B<create_project> or B<create_repo>

Create public empty project. If C<--group>/C<--group-id> is set, project is
created in group directory, else in user directory.

  salsa --user yadd create_project test
  salsa --group js-team --kgb --irc-channel=devscripts create_project test

=item B<delete_project> or B<del_repo>

Delete a project.

=item B<fork>

Forks a project in group/user repository and set "upstream" to original
project. Example:

  $ salsa fork js-team/node-mongodb --verbose
  ...
  salsa.pl info: node-mongodb ready in node-mongodb/
  $ cd node-mongodb
  $ git remote --verbose show
  origin          git@salsa.debian.org:me/node-mongodb (fetch)
  origin          git@salsa.debian.org:me/node-mongodb (push)
  upstream        git@salsa.debian.org:js-team/node-mongodb (fetch)
  upstream        git@salsa.debian.org:js-team/node-mongodb (push)

For a group:

  salsa fork --group js-team user/node-foo

=item B<forks>

List forks of project(s).

  salsa forks qa/qa debian/devscripts

Project can be set using full path or using B<--group>/B<--group-id> or
B<--user>/B<--user-id>, else it is searched in current user namespace.

=item B<push>

Push relevant packaging refs to origin Git remote. To be run from packaging
working directory.

  salsa push

It pushes the following refs to the configured remote for the debian-branch or,
falling back, to the "origin" remote:

=over

=item "master" branch (or whatever is set to debian-branch in gbp.conf)

=item "upstream" branch (or whatever is set to upstream-branch in gbp.conf)

=item "pristine-tar" branch

=item tags named "debian/*" (or whatever is set to debian-tag in gbp.conf)

=item tags named "upstream/*" (or whatever is set to upstream-tag in gbp.conf)

=item all tags, if the package's source format is "3.0 (native)"

=back

=item B<list_projects> or B<list_repos> or B<ls>

Shows projects owned by user or group. If second
argument exists, search only matching projects.

  salsa --group js-team list_projects
  salsa --user yadd list_projects foo*

=item B<last_ci_status>

Displays the last continuous integration result. Use B<--verbose> to see
URL of pipeline when result isn't B<success>. Unless B<--no-fail> is set,
B<salsa last_ci_status> will stop on first "failed" status.

  salsa --group js-team last_ci_status --all --no-fail
  salsa --user yadd last_ci_status foo
  salsa last_ci_status js-team/nodejs

This commands returns the number of "failed" status found. "success" entries
are displayed using STDOUT while other are displayed I<(with details)> using
STDERR. Then you can easily see only failures using:

  salsa --group js-team last_ci_status --all --no-fail >/dev/null

=item B<pipeline_schedule> or B<schedule>

Control pipeline schedule.

=item B<pipeline_schedules> or B<schedules>

Lists current pipeline schedule items.

You can use B<--no-fail> and B<--all> options here.

=item B<merge_request> or B<mr>

Creates a merge request.

Suppose you created a fork using B<salsa fork>, modify some things in a new
branch using one commit and want to propose it to original project
I<(branch "master")>. You just have to launch this in source directory:

  salsa merge_request

Another example:

  salsa merge_request --mr-dst-project debian/foo --mr-dst-branch debian/master

Or simply:

  salsa merge_request debian/foo debian/master

Note that unless destination project has been set using command line,
B<salsa merge_request> will search it in the following order:

=over 4

=item using GitLab API: salsa will detect from where this project was forked

=item using "upstream" origin

=item else salsa will use source project as destination project

=back

To force salsa to use source project as destination project, you can use
"same":

  salsa merge_request --mr-dst-project same
  # or
  salsa merge_request same

New merge request will be created using last commit title and description.

See B<--mr-*> options for more.

=item B<merge_requests> or B<mrs>

List opened merge requests for project(s).

  salsa merge_requests qa/qa debian/devscripts

Project can be set using full path or using B<--group>/B<--group-id> or
B<--user>/B<--user-id>, else it is searched in current user namespace.

=item B<protect_branch>

Protect/unprotect a branch.

=over

=item Protect

  #                                    project      branch merge push
  salsa --group js-team protect_branch node-mongodb master m     d

"merge" and "push" can be one of:

=over

=item B<o>, B<owner>: owner only

=item B<m>, B<maintainer>: B<o> + maintainers allowed

=item B<d>, B<developer>: B<m> + developers allowed

=item B<r>, B<reporter>: B<d> + reporters allowed

=item B<g>, B<guest>: B<r> + guest allowed

=back

=item Unprotect

  salsa --group js-team protect_branch node-mongodb master no

=back

=item B<protected_branches>

List protected branches:

  salsa --group js-team protected_branches node-mongodb

=item B<push_repo>

Create a new project from a local Debian source directory configured with
git.

B<push_repo> executes the following steps:

=over

=item gets project name using debian/changelog file;

=item launches B<git remote add upstream ...>;

=item launches B<create_project>;

=item pushes local repository.

=back

Examples:

  salsa --user yadd push_repo ./test
  salsa --group js-team --kgb --irc-channel=devscripts push_repo .

=item B<rename_branch>

Rename branch given in B<--source-branch> with name given in B<--dest-branch>.
You can use B<--no-fail>, B<--all> and B<--all-archived> options here.

=item B<search_projects> or B<search_repo> or B<search>

Search for a project using given string. Shows name, owner ID and other
information.

  salsa search_projects devscripts
  salsa search_projects debian/devscripts
  salsa search_projects 18475

=item B<update_projects> or B<update_repo>

Configure projects using parameters given to command line.
A project name has to be given unless B<--all> or B<--all-archived> is set. Prefer to use
B<update_safe>.

  salsa --user yadd --tagpending --kgb --irc=devscripts update_projects test
  salsa --group js-team update_projects --all
  salsa --group js-team --rename-head update_projects test1 test2 test3
  salsa update_projects js-team/node-mongodb --kgb --irc debian-js

By default when using B<--all>, salsa will fail on first error. If you want
to continue, set B<--no-fail>. In this case, salsa will display a warning for
each project that has fail but continue with next project. Then to see full
errors, set B<--verbose>.

=item B<update_safe>

Launch B<check_projects> and ask before launching B<update_projects> (unless B<--yes>).

  salsa --user yadd --tagpending --kgb --irc=devscripts update_safe test
  salsa --group js-team update_safe --all
  salsa --group js-team --rename-head update_safe test1 test2 test3
  salsa update_safe js-team/node-mongodb --kgb --irc debian-js

=back

=head2 Other

=over

=item B<purge_cache>

Empty local cache.

=back

=head1 OPTIONS

=head2 General options

=over

=item B<--chdir> or B<-C>

Change directory before launching command:

  salsa --chdir ~/debian checkout debian/libapache2-mod-fcgid

=item B<--cache-file>

File to store cached values. An empty value disables cache.
Default: C<~/.cache/salsa.json>.

C<.devscripts> value: B<SALSA_CACHE_FILE>

=item B<--no-cache>

Disable cache usage. Same as B<--cache-file ''>

=item B<--conf-file> or B<--conffile>

Add or replace default configuration files.
This can only be used as the first option given on the
command-line.
Default: C</etc/devscripts.conf> and C<~/.devscripts>.

=over

=item replace:

  salsa --conf-file test.conf <command>...
  salsa --conf-file test.conf --conf-file test2.conf  <command>...

=item add:

  salsa --conf-file +test.conf <command>...
  salsa --conf-file +test.conf --conf-file +test2.conf  <command>...

If one B<--conf-file> has no C<+>, default configuration files are ignored.

=back

=item B<--no-conf> or B<--noconf>

Don't read any configuration files. This can only be used as the first option
given on the command-line.

=item B<--debug>

Enable debugging output.

=item B<--group>

Team to use. Use C<salsa search_groups name> to find it.

If you want to use a subgroup, you have to set its full path:

  salsa --group perl-team/modules/packages check_projects lemonldap-ng

C<.devscripts> value: B<SALSA_GROUP>

Be careful when you use B<SALSA_GROUP> in your C<.devscripts> file. Every
B<salsa> command will be executed in group space, for example if you want to
propose a little change in a project using B<salsa fork> + B<salsa merge_request>, this
"fork" will be done in group space unless you set a B<--user>/B<--user-id>.
Prefer to use an alias in your C<.bashrc> file. Example:

  alias jsteam_admin="salsa --group js-team"

or

  alias jsteam_admin="salsa --conf-file ~/.js.conf

or to use both .devscripts and .js.conf:

  alias jsteam_admin="salsa --conf-file +~/.js.conf

then you can fix B<SALSA_GROUP> in C<~/.js.conf>

To enable bash completion for your alias, add this in your .bashrc file:

  _completion_loader salsa
  complete -F _salsa_completion jsteam_admin

=item B<--group-id>

Group ID to use. Use C<salsa search_groups name> to find it.

C<.devscripts> value: B<SALSA_GROUP_ID>

Be careful when you use B<SALSA_GROUP_ID> in your C<.devscripts> file. Every
B<salsa> command will be executed in group space, for example if you want to
propose a little change in a project using B<salsa fork> + B<salsa merge_request>, this
"fork" will be done in group space unless you set a B<--user>/B<--user-id>.
Prefer to use an alias in your C<.bashrc> file. Example:

  alias jsteam_admin="salsa --group-id 2666"

or

  alias jsteam_admin="salsa --conf-file ~/.js.conf

then you can fix B<SALSA_GROUP_ID> in C<~/.js.conf>.

=item B<--help>

Displays this manpage.

=item B<--info> or B<-i>

Prompt before sensible changes.

C<.devscripts> value: B<SALSA_INFO> (yes/no)

=item B<--path>

Repository path.
Default to group or user path.

C<.devscripts> value: B<SALSA_REPO_PATH>

=item B<--token>

Token value (see above).

=item B<--token-file>

File to find token (see above).

=item B<--user>

Username to use. If neither B<--group>, B<--group-id>, B<--user> or B<--user-id>
is set, salsa uses current user ID (corresponding to salsa private token).

=item B<--user-id>

User ID to use. Use C<salsa search_users name> to find one. If neither
B<--group>, B<--group-id>, B<--user> or B<--user-id> is set, salsa uses current
user ID (corresponding to salsa private token).

C<.devscripts> value: B<SALSA_USER_ID>

=item B<--verbose>

Enable verbose output.

=item B<--yes>

Never ask for consent.

C<.devscripts> value: B<SALSA_YES> (yes/no)

=back

=head2 List/search project options

=over

=item B<--archived>, B<--no-archived>

Instead of looking to active projects, list or search in archived projects.
Note that you can't have both archived and unarchived projects in the same
request.
Default: no I<(ie --no-archived)>.

C<.devscripts> value: B<SALSA_ARCHIVED> (yes/no)

=back

=head2 Update/create project options

=over

=item B<--all>, B<--all-archived>

When set, all projects of group/user are affected by command.
B<--all> will filter all active projects, whereas B<--all-archived> will
include active and archived projects.

=over

=item B<--skip>, B<--no-skip>

Ignore project with B<--all> or B<--all-achived>. Example:

  salsa update_projects --tagpending --all --skip qa --skip devscripts

To set multiples values, use spaces. Example:

  SALSA_SKIP=qa devscripts

Using B<--no-skip> will ignore any projects to be skipped and include them.

C<.devscripts> value: B<SALSA_SKIP>

=item B<--skip-file>

Ignore projects in this file (1 project per line).

  salsa update_projects --tagpending --all --skip-file ~/.skip

C<.devscripts> value: B<SALSA_SKIP_FILE>

=back

=item B<--build-timeout>

The maximum amount of time, in seconds, that a job can run.
Default: 3600 (60 minutes).

  salsa update_safe myrepo --build-timeout 3600

C<.devscripts> value: B<SALSA_BUILD_TIMEOUT>

=item B<--avatar-path>

Path to an image for the project's avatar.
If path value contains "%p", it is replaced by project name.

C<.devscripts> value: B<SALSA_AVATAR_PATH>

=item B<--ci-config-path>

Configure configuration file path of GitLab CI.
Default: empty.
Example:

  salsa update_safe --ci-config-path recipes/debian.yml@salsa-ci-team/pipeline debian/devscripts

C<.devscripts> value: B<SALSA_CI_CONFIG_PATH>

=item B<--desc>, B<--no-desc>

Configure a project's description using pattern given in B<desc-pattern>.

C<.devscripts> value: B<SALSA_DESC> (yes/no)

=item B<--desc-pattern>

Project's description pattern. "%p" is replaced by project's name,
while "%P" is replaced by project's name given in command
(may contains full path).
Default: "Debian package %p".

C<.devscripts> value: B<SALSA_DESC_PATTERN>

=item B<--email>, B<--no-email>, B<--disable-email>

Enable, ignore or disable email-on-push.

C<.devscripts> value: B<SALSA_EMAIL> (yes/ignore/no, default: ignore)

=item B<--email-recipient>

Email-on-push recipient. Can be multi valued:

  $ salsa update_safe myrepo \
        --email-recipient foo@foobar.org \
        --email-recipient bar@foobar.org

If recipient value contains "%p", it is replaced by project name.

C<.devscripts> value: B<SALSA_EMAIL_RECIPIENTS> (use spaces to separate
multiples recipients)

=item B<--analytics>

Set analytics feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_ANALYTICS> (yes/private/no, default: yes)

=item B<--auto-devops>

Set auto devops feature.

C<.devscripts> value: B<SALSA_ENABLE_AUTO_DEVOPS> (yes/no, default: yes)

=item B<--container>

Set container feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_CONTAINER> (yes/private/no, default: yes)

=item B<--environments>

Set environments feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_ENVIRONMENTS> (yes/private/no, default: yes)

=item B<--feature-flags>

Set feature flags feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_FEATURE_FLAGS> (yes/private/no, default: yes)

=item B<--forks>

Set forking a project feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_FORKS> (yes/private/no, default: yes)

=item B<--infrastructure>

Set infrastructure feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_INFRASTRUCTURE> (yes/private/no, default: yes)

=item B<--issues>

Set issues feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_ISSUES> (yes/private/no, default: yes)

=item B<--jobs>

Set jobs feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_JOBS> (yes/private/no, default: yes)

=item B<--lfs>

Set Large File Storage (LFS) feature.

C<.devscripts> value: B<SALSA_ENABLE_LFS> (yes/no, default: yes)

=item B<--mr>

Set merge requests feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_MR> (yes/private/no, default: yes)

=item B<--monitor>

Set monitor feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_MONITOR> (yes/private/no, default: yes)

=item B<--packages>

Set packages feature.

C<.devscripts> value: B<SALSA_ENABLE_PACKAGES> (yes/no, default: yes)

=item B<--pages>

Set pages feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_PAGES> (yes/private/no, default: yes)

=item B<--releases>

Set releases feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_RELEASES> (yes/private/no, default: yes)

=item B<--enable-remove-source-branch>, B<--disable-remove-source-branch>

Enable or disable deleting source branch option by default for all new merge
requests.

C<.devscripts> value: B<SALSA_REMOVE_SOURCE_BRANCH> (yes/no, default: yes)

=item B<--repo>

Set the project's repository feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_REPO> (yes/private/no, default: yes)

=item B<--request-access>

Allow users to request member access.

C<.devscripts> value: B<SALSA_REQUEST_ACCESS> (yes/no)

=item B<--requirements>

Set requirements feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_REQUIREMENTS> (yes/private/no, default: yes)

=item B<--security-compliance>

Enable or disabled Security and Compliance feature.

C<.devscripts> value: B<SALSA_ENABLE_SECURITY_COMPLIANCE> (yes/no)

=item B<--service-desk>

Allow service desk feature.

C<.devscripts> value: B<SALSA_ENABLE_SERVICE_DESK> (yes/no)

=item B<--snippets>

Set snippets feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_SNIPPETS> (yes/private/no, default: yes)

=item B<--wiki>

Set wiki feature with permissions.

C<.devscripts> value: B<SALSA_ENABLE_WIKI> (yes/private/no, default: yes)

=item B<--irc-channel>

IRC channel for KGB or Irker. Can be used more than one time only with
B<--irker>.

B<Important>: channel must not include the first "#". If salsa finds a channel
starting with "#", it will consider that the channel starts with 2 "#"!

C<.devscript> value: B<SALSA_IRC_CHANNEL>

Multiple values must be space separated.

Since configuration files are read using B<sh>, be careful when using "#": you
must enclose the channel with quotes, else B<sh> will consider it as a comment
and will ignore this value.

=item B<--irker>, B<--no-irker>, B<--disable-irker>

Enable, ignore or disable Irker service.

C<.devscripts> value: B<SALSA_IRKER> (yes/ignore/no, default: ignore)

=item B<--irker-host>

Irker host.
Default: ruprecht.snow-crash.org.

C<.devscripts> value: B<SALSA_IRKER_HOST>

=item B<--irker-port>

Irker port.
Default: empty (default value).

C<.devscripts> value: B<SALSA_IRKER_PORT>

=item B<--kgb>, B<--no-kgb>, B<--disable-kgb>

Enable, ignore or disable KGB webhook.

C<.devscripts> value: B<SALSA_KGB> (yes/ignore/no, default: ignore)

=item B<--kgb-options>

List of KGB enabled options (comma separated).
Default: issues_events, merge_requests_events, note_events,
pipeline_events, push_events, tag_push_events, wiki_page_events,
enable_ssl_verification

  $ salsa update_safe debian/devscripts --kgb --irc-channel devscripts \
    --kgb-options 'merge_requests_events,issues_events,enable_ssl_verification'

List of available options: confidential_comments_events,
confidential_issues_events, confidential_note_events, enable_ssl_verification,
issues_events, job_events, merge_requests_events, note_events, pipeline_events,
tag_push_events, wiki_page_events

C<.devscripts> value: B<SALSA_KGB_OPTIONS>

=item B<--no-fail>

Don't stop on error when using B<update_projects> with B<--all> or B<--all-archived>
when set to yes.

C<.devscripts> value: B<SALSA_NO_FAIL> (yes/no, default: no)

=item B<--rename-head>, B<--no-rename-head>

Rename HEAD branch given by B<--source-branch> into B<--dest-branch> and change
"default branch" of project. Works only with B<update_projects>.

C<.devscripts> value: B<SALSA_RENAME_HEAD> (yes/no)

=over

=item B<--source-branch>

Default: "master".

C<.devscripts> value: B<SALSA_SOURCE_BRANCH>

=item B<--dest-branch>

Default: "debian/master".

C<.devscripts> value: B<SALSA_DEST_BRANCH>

=back

=item B<--tagpending>, B<--no-tagpending>, B<--disable-tagpending>

Enable, ignore or disable "tagpending" webhook.

C<.devscripts> value: B<SALSA_TAGPENDING> (yes/ignore/no, default: ignore)

=back

=head2 Pipeline schedules

=over

=item B<--schedule-desc>

Description of the pipeline schedule.

=item B<--schedule-ref>

Branch or tag name that is triggered.

=item B<--schedule-cron>

Cron schedule. Example:

  0 1 * * *.

=item B<--schedule-tz>

Time zone to run cron schedule.
Default: UTC.

=item B<--schedule-enable>, B<--schedule-disable>

Enable/disable the pipeline schedule to run.
Default: disabled.

=item B<--schedule-run>

Trigger B<--schedule-desc> scheduled pipeline to run immediately.
Default: false.

=item B<--schedule-delete>

Delete B<--schedule-desc> pipeline schedule.

=back

=head2 Merge requests options

=over

=item B<--mr-title>

Title for merge request.
Default: last commit title.

=item B<--mr-desc>

Description of new MR.
Default:

=over

=item empty if B<--mr-title> is set

=item last commit description if any

=back

=item B<--mr-dst-branch> (or second command line argument)

Destination branch.
Default: "master".

=item B<--mr-dst-project> (or first command line argument)

Destination project.
Default: project from which the current project was forked; or,
if not found, "upstream" value found using B<git remote --verbose show>;
or using source project.

If B<--mr-dst-project> is set to B<same>, salsa will use source project as
destination.

=item B<--mr-src-branch>

Source branch.
Default: current branch.

=item B<--mr-src-project>

Source project.
Default: current project found using
B<git remote --verbose show>.

=item B<--mr-allow-squash>, B<--no-mr-allow-squash>

Allow upstream project to squash your commits, this is the default.

C<.devscripts> value: B<SALSA_MR_ALLOW_SQUASH> (yes/no)

=item B<--mr-remove-source-branch>, B<--no-mr-remove-source-branch>

Remove source branch if merge request is accepted.
Default: no.

C<.devscripts> value: B<SALSA_MR_REMOVE_SOURCE_BRANCH> (yes/no)

=back

=head2 Options to manage other GitLab instances

=over

=item B<--api-url>

GitLab API.
Default: L<https://salsa.debian.org/api/v4>.

C<.devscripts> value: B<SALSA_API_URL>

=item B<--git-server-url>

Default: "git@salsa.debian.org:".

C<.devscripts> value: B<SALSA_GIT_SERVER_URL>

=item B<--irker-server-url>

Default: "ircs://irc.oftc.net:6697/".

C<.devscripts> value: B<SALSA_IRKER_SERVER_URL>

=item B<--kgb-server-url>

Default: L<https://kgb.debian.net/webhook/?channel=>.

C<.devscripts> value: B<SALSA_KGB_SERVER_URL>

=item B<--tagpending-server-url>

Default: L<https://webhook.salsa.debian.org/tagpending/>.

C<.devscripts> value: B<SALSA_TAGPENDING_SERVER_URL>

=back

=head3 Configuration file example

Example to use salsa with L<https://gitlab.ow2.org> (group "lemonldap-ng"):

  SALSA_TOKEN=`cat ~/.ow2-gitlab-token`
  SALSA_API_URL=https://gitlab.ow2.org/api/v4
  SALSA_GIT_SERVER_URL=git@gitlab.ow2.org:
  SALSA_GROUP_ID=34

Then to use it, add something like this in your C<.bashrc> file:

  alias llng_admin='salsa --conffile ~/.salsa-ow2.conf'

=head1 SEE ALSO

B<dpt-salsa>

=head1 AUTHOR

Xavier Guimard E<lt>yadd@debian.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, Xavier Guimard E<lt>yadd@debian.orgE<gt>

It contains code formerly found in L<dpt-salsa> I<(pkg-perl-tools)>
copyright 2018, gregor herrmann E<lt>gregoa@debian.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut

use Devscripts::Salsa;

exit Devscripts::Salsa->new->run;
