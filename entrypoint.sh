#!/usr/bin/env bash

set -x

# Copies settings files with some predefined database configuration
# which assumes this action will run in a workflow containing a
# service named "mysql", running MySQL with valid databases for
# the site we want to apply the security updates to. The database names
# are assumed to be "drupal" and "civicrm".
cp /{,civicrm.}settings.php "$GITHUB_WORKSPACE/sites/default/"

[ -z "$GITHUB_TOKEN" ] && echo "Missing Github Token" && exit 1

git fetch origin --tags

base_branch_or_tag=$(git describe --tags --abbrev=0 2> /dev/null || true)

# If there are no tags in this repo, use master instead
[ -z "$base_branch_or_tag" ] && base_branch_or_tag=master

security_updates_branch="${base_branch_or_tag}_security_updates"

# If there's a branch with security updates for the base branch/tag already,
# we just check it out, otherwise we create a new one
# Important: This piece of code assumes the action will be run from
# a non-shallow clone pointing to master.
if [ -z "$(git ls-remote origin $security_updates_branch)" ]
then
    git checkout -f -B $security_updates_branch $base_branch_or_tag
else
    git checkout $security_updates_branch
fi

# The action is supposed to be run together with a mysql-anondb
# container.
# The db in this container might have these variables set to a
# directory that is not available during the execution of the
# script, so we force them to point to a location that:
# 1) We're sure it exists
# 2) We know we have write/read permissions
#
# Without this, we might run into permission issues while running
# commands like drush cc or updb
drush vset file_temporary_path /tmp
drush vset file_private_path /tmp

# Since we've switched to a new branch, let's first run basic updates
# to ensure we'll be able to check for modules updates
drush cc all
drush updb -y

# First, we just check which updates are available so we can build
# a nice update message for the commit and Pull Request
drush pm-updatestatus --security-only --format=csv | php /build-update-message.php > /update-message.txt

# Do the actual update of modules
drush pm-updatecode --security-only -y

# Drupal core updates will revert any customizations made to the .gitignore
# file, so we need to make sure of undoing that. It's safe to always run
# this, as it will just exit silently if there are no changes
# See: https://www.drupal.org/project/drupal/issues/1170538
git checkout -- .gitignore

# Let's remove the settings files created by this script so they won't get
# committed by mistake in case they are not ignored by git
rm -f "$GITHUB_WORKSPACE/sites/default/"{,civicrm.}settings.php

git add .

# Exit if there are no changes to be committed (i.e. no security updates)
git diff --cached --exit-code > /dev/null && exit 0

# Sets github user for commit
git config --local user.email "info@compucorp.co.uk"
git config --local user.name "Drupal 7 Security Updates"

# Pipes a commit-message containing a Subject line and a body with the list of updated modules
cat <(printf "Automated Security Update\n\n") /update-message.txt | git commit -F -

# Push the branch using the token created for the job run
remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git push "${remote_repo}" HEAD:$security_updates_branch

echo "::set-output name=branch::$security_updates_branch"

# Let people know how the branch was created and how to fix conflicts, if there are any
if [ $base_branch_or_tag != "master" ]
then
  (cat <<PRNOTE

## Important notes

This update was created from the \`$base_branch_or_tag\` tag. Conflicts are expected in case \`master\` is ahead the tag. If that is the case, the conflicts should be manually fixed in a new branch.

Also, keep in mind that the diff displayed by github might not reflect the reality. This is due to [how Github does the comparisons](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/about-comparing-branches-in-pull-requests#three-dot-and-two-dot-git-diff-comparisons):

> By default, pull requests on GitHub show a three-dot diff, or a comparison between the most recent version of the topic branch and the commit where the topic branch was last synced with the base branch.

In other words, the comparison will show the differences between the security updates branch and master, as it was when the tag was created rather than **how it is today**. This might end up in Github saying the Pull Request can be merged successfully, while it actually has conflicts. To fix this, you'll need to rebase the security updates branch on top of \`master\`.
PRNOTE
) >> /update-message.txt

fi

pull_request_url=$(php /create-pull-request.php -h $security_updates_branch < /update-message.txt)

echo "::set-output name=pull-request::$pull_request_url"
