#!/bin/bash

# This program is used to check that a git repository follows the DEP-14 branch
# naming scheme. If not, it suggests how to convert it.

# Debian dep14-convert.  Copyright (C) 2024-2025 Otto Kekäläinen.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

# Abort if anything goes wrong
set -euo pipefail

readonly PROGNAME=$(basename "$0")
readonly REQUIRED_FILES=("debian/source/format" "debian/control")

# Global variables
declare -a COMMANDS=()
declare -x SALSA_PROJECT=""
declare debian_branch=""
declare upstream_branch=""
declare APPLY=""
declare DEBUG=""

declare dep14_debian_branch="debian/latest"

stderr() {
  echo "$@" >&2
}

error() {
  stderr "ERROR: $*"
}

debug() {
    if [[ -n "$DEBUG" ]]
    then
      if [ -z "$*" ]
      then
        stderr
      else
        stderr "DEBUG: $*"
      fi
  fi
}

die() {
  error "$*"
  exit 1
}


usage() {
  printf "%s\n" \
"Usage: $PROGNAME [options]

This helper tool assists in renaming the branch names by printing the necessary
git commands for local repository and salsa commands remote repository to rename
the branches and to update the default git branch. It also prints commands to
create a gbp.conf with matching branch names.

As this script does not actually modify anything, so feel free to run this
script in any Debian packaging repository to see what it outputs.

For DEP-14 purpose and details, please see
https://dep-team.pages.debian.net/deps/dep14/

Options:
    --packaging-branch <name>    Branch for main packaging (e.g. '${dep14_debian_branch}')

    --debug     Display debug information while running
    -h, --help  Display this help message
    --version   Display version information"
}

version() {
  printf "%s\n" \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2024-2025 by Otto Kekäläinen, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 3 or later."
}

check_requirements() {
  # Check if we're in a git repository
  if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1
  then
    die "Not in a git repository. Please run this script from within a git repository"
  fi

  # Check for required files
  for file in "${REQUIRED_FILES[@]}"
  do
    if [[ ! -f "$file" ]]
    then
      die "Required file $file not found"
    fi
  done
}

# Given the output from 'git ls-remote --get-url', parse the Salsa project slug
# Examples:
#   https://salsa.debian.org/games-team/vcmi.git => games-team/vcmi
#   git@salsa.debian.org:games-team/vcmi.git     => games-team/vcmi
find_salsa_remote() {
  # Populate SALSA_PROJECT only if it contained a Salsa address, otherwise
  # keep it empty to prevent garbage from being passed on
  case "$1" in
    "git@salsa.debian.org:"*)
      SALSA_PROJECT="${1##git@salsa.debian.org:}"
      ;;
    "https://salsa.debian.org/"*)
      SALSA_PROJECT="${1##https://salsa.debian.org/}"
      ;;
  esac
  SALSA_PROJECT="${SALSA_PROJECT%%.git}"
  echo $SALSA_PROJECT
}

# Find the most likely branch used for unstable uploads
find_debian_branch() {
  local debian_branch=""

  debug "Running find_debian_branch()"

  # if debian/gbp.conf exists, use value of debian-branch
  if [[ -f debian/gbp.conf ]] && grep -q "^debian-branch" debian/gbp.conf
  then
    debian_branch=$(grep -oP "^debian-branch[[:space:]]*=[[:space:]]*\K.*" debian/gbp.conf)
    debug "debian/gbp.conf exists and has debian-branch '$debian_branch'"

    if git rev-parse --verify "$debian_branch" > /dev/null 2>&1
    then
      echo "$debian_branch"
      return
    fi
  fi

  # check debian/changelog on common branches
  # and if the changelog targeted 'unstable'
  local branches="debian debian/sid debian/unstable debian/master master main"

  for branch in $branches
  do
    debug "Check debian/changelog on branch '$branch'"

    # Check if the branch has debian/changelog
    local git_contents=$(git ls-tree -r $branch 2>&1 | grep "debian/changelog")
    if [[ -n "$git_contents" ]]
    then
      local changelog_content=$(git show "$branch:debian/changelog")
      local distribution=$(echo "$changelog_content" | \
        grep "^[a-z]" | \
        cut -d ' ' -f 3 | \
        grep -v UNRELEASED | \
        grep -v experimental | \
        grep -m 1 -o "[a-z-]*"
      )

      debug "Found distribution '$distribution'"

      if [[ "$distribution" == "unstable" ]]
      then
        debian_branch="$branch"
        echo "$debian_branch"
        return
      fi
    fi
  done
}

# Find the most likely branch used for upstream releases
# - if debian/gbp.conf exists, use value of upstream-branch
# - check if common branches (upstream, master, main) recently merged on the
#   assumed debian branch
find_upstream_branch() {
  local debian_branch="$1"
  local branches=$(git branch --list --format="%(refname:short)")
  local upstream_branch=""

  debug "Running find_upstream_branch()"

  # if debian/gbp.conf exists on debian branch, use value of upstream-branch
  if [[ -n "$debian_branch" ]] && git show "$debian_branch:debian/gbp.conf" 2>/dev/null | grep "^upstream-branch" > /dev/null
  then
    upstream_branch=$(git show "$debian_branch:debian/gbp.conf" | grep -oP "^upstream-branch[[:space:]]*=[[:space:]]*\K.*")

    debug "Check debian/gbp.conf upstream-branch '$upstream_branch'"

    if git rev-parse --verify "$upstream_branch" >/dev/null 2>&1
    then
      echo "$upstream_branch"
      return
    fi
  fi

  # Check which branch that modified files outside of debian/ was most
  # recently merged on the debian branch, but cap checks to 50 most recent
  # merges
  merge_commits=$(git log --merges --format="%H" -50 $debian_branch)

  # Iterate through the merge commits
  for commit in $merge_commits
  do
    debug "Check parents of merge commit '$merge_commits'"

    # Get the two parent commits
    parent1=$(git rev-parse $commit^1)
    parent2=$(git rev-parse $commit^2)

    if [[ -n "$DEBUG" ]]
    then
      debug
      debug "commit $commit"
      debug git log -1 --oneline $parent1
      git log -1 --oneline $parent1 >&2
      debug git log -1 --oneline $parent2
      git log -1 --oneline $parent2 >&2
    fi

    # Check if any files outside debian/ were changed as a result of the merge
    changed_files=$(git diff --name-only --diff-filter=ACMRTUXB $parent1...$commit | grep -v "^debian/")

    # If there are changed files outside debian/, break the loop
    if [[ -n "$changed_files" ]]
    then
      debug "First merge affecting files outside debian/: $commit"

      # Get the branch names that decent from the merge commit
      merge_branches=$(git branch --list --format="%(refname:short)" --contains $parent2)
      #debug "merge_branches: $merge_branches"

      for branch in $merge_branches
      do
        # If only one branch was found, it must be it
        if [[ "$branch" == "$merge_branches" ]]
        then
          upstream_branch="$branch"
          break
        fi

        # If branch has no debian/changelog, assume it was the upstream branch
        local git_contents=$(git ls-tree -r $branch 2>&1 | grep "debian/changelog")
        if [[ -z "$git_contents" ]]
        then
          debug "Found branch '$branch' with no 'debian/changelog'"
          upstream_branch="$branch"
          break
        fi
      done

      echo "$upstream_branch"
      return
    fi
  done

  debug "No merge commits found on the Debian packaging branch '$debian_branch'"

  if git rev-parse --verify "upstream" > /dev/null 2>&1
  then
    debug "Using 'upstream' branch despite it not having merge commits on '$debian_branch'"
    echo "upstream"
    return
  fi
}

# Parse command line arguments
while :
do
  case "${1:-}" in
    --apply)
      # @TODO: Not implemented yet
      APPLY=1
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --version)
      version
      exit 0
      ;;
    --packaging-branch)
      shift
      dep14_debian_branch="$1"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

# Main script execution starts here
check_requirements

# Check if we have a valid packaging branch name
git check-ref-format --branch "$dep14_debian_branch" >/dev/null

# Check if package is native
if grep -qF native debian/source/format 2>/dev/null
then
  stderr "DEP-14 is not applicable to native Debian packages."
  grep -HF native debian/source/format
  exit 0
fi

# Check for problematic upstream remote
if git remote get-url upstream > /dev/null 2>&1
then
  stderr "WARNING: There is a remote called 'upstream', which may interfere with branch names 'upstream/*'."
  stderr "Please rename the remote by running: git remote rename upstream upstreamvcs"
  stderr
fi

# Check branch count
local_branches=$(git branch --list --format="%(refname:short)")
branch_count=$(echo "$local_branches" | wc -l)
if [[ "$branch_count" -gt 1 ]]
then
  stderr "The git repository has the following local branches:" $local_branches
  stderr
else
  error "To identify the correct debian and upstream branches, there needs to be at least two local branches."
  stderr "Currently there are only: " $local_branches
  exit 1
fi

# Print DEP-14 requirements
cat >/dev/stderr << 'EOF'
In DEP-14, these branches should exist in the Debian packaging repository:

* debian/latest   Used to create the *.debian.tar.xz that contains the Debian
                  packaging code from the debian/ directory, and which is
                  uploaded to Debian unstable (or occasionally to experimental).
                  DEP-14 also allows using branch names debian/unstable
                  or debian/experimental.
* upstream/latest Used to create the *.orig.tar.gz that contains the unmodified
                  source code of the specific upstream release.

Optionally, DEP-14 suggests the following branch:

* pristine-tar    Contains xdelta data for making the release tarball
                  bit-for-bit identical with the original one, so that the
                  upstream *.orig.tar.gz.asc signature can be validated.

Other branches may also exist, but are not required.

EOF

# Check debian/latest branch
stderr -n "-> Branch ${dep14_debian_branch}: "
if git show-ref --verify --quiet refs/heads/${dep14_debian_branch}
then
  stderr "exists"
  debian_branch="${dep14_debian_branch}"
else
  stderr -n "missing"
  debian_branch=$(find_debian_branch)

  if [[ -n "$debian_branch" ]]
  then
    stderr ", presumably '$debian_branch' should be renamed"
    COMMANDS+=("git branch -m $debian_branch ${dep14_debian_branch}")

    # Get Salsa project name primarily from git remote
    SALSA_PROJECT="$(find_salsa_remote "$(git ls-remote --get-url)")"

    # If nothing matched, maybe there's another remote
    if [[ -z "$SALSA_PROJECT" ]]
    then
      debug "Current git remote not on Salsa, check other remotes"
      SALSA_PROJECT=$(
        git remote show -n | while read -r remote
        do
          find_salsa_remote "$(git ls-remote --get-url $remote)" && break || true
        done
      )
    fi

    # If nothing matched, fall back to Vcs-Git field
    if [[ -z "$SALSA_PROJECT" ]]
    then
      debug "No git remote on Salsa, using Vcs-Git for SALSA_PROJECT instead"
      SALSA_PROJECT=$(find_salsa_remote "$(git show "$debian_branch:debian/control" | grep -oP 'Vcs-Git: \K(.+salsa\.debian\.org.+)')" || true)
    fi

    if [[ -n "$SALSA_PROJECT" ]]
    then
      # Unprotecting the branch is a bit ugly, but this is how 'salsa' in
      # devscripts works
      COMMANDS+=("salsa protect_branch $SALSA_PROJECT $debian_branch no # (intentionally fails with error 404 if branch wasn't protected)")
      COMMANDS+=("salsa rename_branch $SALSA_PROJECT --source-branch=$debian_branch --dest-branch=${dep14_debian_branch}")
      COMMANDS+=("salsa update_repo $SALSA_PROJECT --rename-head --source-branch=$debian_branch --dest-branch=${dep14_debian_branch}")
    fi
  else
    stderr
    die "Could not find the current debian branch"
  fi
fi

# Check upstream/latest branch
stderr -n "-> Branch upstream/latest: "
if git show-ref --verify --quiet refs/heads/upstream/latest
then
  stderr "exists"
else
  stderr -n "missing"
  upstream_branch=$(find_upstream_branch "$debian_branch")

  if [[ -n "$upstream_branch" ]]
  then
    stderr ", presumably '$upstream_branch' should be renamed"
    COMMANDS+=("git branch -m $upstream_branch upstream/latest")

    if [[ -n "$SALSA_PROJECT" ]]
    then
      # Rename to temporary name before using final name to avoid API error:
      #   (HTTP 400): Bad Request {"message":"Failed to create branch 'upstream/latest'
      COMMANDS+=("salsa rename_branch $SALSA_PROJECT --source-branch=$upstream_branch --dest-branch=temporary")
      COMMANDS+=("salsa rename_branch $SALSA_PROJECT --source-branch=temporary --dest-branch=upstream/latest")
    fi
  else
    stderr
    die "Could not find the current upstream branch"
  fi
fi

# Check gbp.conf configuration
stderr -n "-> Configuration file debian/gbp.conf: "
gbp_conf_defaultsection=false
if git ls-tree -r "$debian_branch" 2>&1 | grep "debian/gbp.conf" > /dev/null
then
  stderr -n "exists "
  if git show "$debian_branch:debian/gbp.conf" | grep -qP "^debian-branch[[:space:]]*=[[:space:]]*${dep14_debian_branch}" &&
     git show "$debian_branch:debian/gbp.conf" | grep -qP "^upstream-branch[[:space:]]*=[[:space:]]*upstream/latest"
  then
    stderr "and 'debian-branch' and 'upstream-branch' are correctly configured"
  else
    stderr "but 'debian-branch' or 'upstream-branch' does not have correct values"
    COMMANDS+=("git checkout ${dep14_debian_branch}")

    if git show "$debian_branch:debian/gbp.conf" | grep -qP "^debian-branch[[:space:]]*="
    then
      COMMANDS+=("sed -i 's/^debian-branch[[:space:]]*=.*/debian-branch = debian\/latest/' debian/gbp.conf")
    else
      test "${gbp_conf_defaultsection}" == "true" || COMMANDS+=('echo "[DEFAULT]" >> debian/gbp.conf') && gbp_conf_defaultsection=true
      COMMANDS+=("echo \"debian-branch = ${dep14_debian_branch}\" >> debian/gbp.conf")
    fi

    if git show "$debian_branch:debian/gbp.conf" | grep -qP "^upstream-branch[[:space:]]*="
    then
      COMMANDS+=("sed -i 's/^upstream-branch[[:space:]]*=.*/upstream-branch = upstream\/latest/' debian/gbp.conf")
    else
      test "${gbp_conf_defaultsection}" == "true" || COMMANDS+=('echo "[DEFAULT]" >> debian/gbp.conf') && gbp_conf_defaultsection=true
      COMMANDS+=('echo "upstream-branch = upstream/latest" >> debian/gbp.conf')
    fi
  fi
else
  stderr "missing"
  COMMANDS+=("git checkout ${dep14_debian_branch}")
  COMMANDS+=('echo "[DEFAULT]" > debian/gbp.conf')
  COMMANDS+=("echo \"debian-branch = ${dep14_debian_branch}\" >> debian/gbp.conf")
  COMMANDS+=('echo "upstream-branch = upstream/latest" >> debian/gbp.conf')
fi

# If any commands modified gbp.conf, ensure last command commits everything in git
if echo "${COMMANDS[@]}" | grep --quiet --fixed-strings gbp.conf
then
  COMMANDS+=('git commit -a -m "Update git repository layout to follow DEP-14"')
fi

# If any commands ran 'salsa', ensure remote deletes propagate to local git
if echo "${COMMANDS[@]}" | grep --quiet --fixed-strings 'salsa '
then
  COMMANDS+=('git pull --prune')
fi

# Blank newline to make output more readable
stderr

# Handle results
if [[ ${#COMMANDS[@]} -eq 0 ]]
then
  stderr "Repository is DEP-14 compliant."
else
  if [[ -z "$APPLY" ]]
  then
    stderr "Run the following commands to make the repository follow DEP-14:"
    printf "    %s\n" "${COMMANDS[@]}"
  else
    die "Using --apply has not yet been implemented"
    # @TODO: Run commands automatically once we have enough confidence they
    # always work
  fi
fi

if [[ -n "$SALSA_PROJECT" ]]
then
  stderr
  stderr "For accurate results, ensure your local git checkout is in sync with Salsa project $SALSA_PROJECT."
fi


# Note the developers: When testing changes to this script, a good way to test
# the integration with Salsa is to fork the project
# https://salsa.debian.org/sudo-team/sudo, and in your
# `path-to-fork/-/settings/repository` add `master` as a protected branch. This
# way the salsa API calls will mimic the scenario a typical rename would run
# into. You can delete the fork and create fresh forks for every test as many
# times as needed.
