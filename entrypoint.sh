#!/usr/bin/env bash

# Copies a settings file with some predefined database configuration
# which assumes this action will run in a workflow containing a
# service named "mysql", running MySQL with a valid database for
# the site we want to apply the security updates to. The database name
# is assumed to be "drupal".
cp /settings.php "$GITHUB_WORKSPACE/sites/default/settings.php"

set -x

# $1 is the github_token param passed to the action via
[ -z "$1" ] && echo "Missing Github Token" && exit 1

export GITHUB_TOKEN=$1

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

# Since we've switched to a new branch, let's first run basic updates
# to ensure we'll be able to check for modules updates
drush cc all
drush updb -y

# First, we just check which updates are available so we can build
# a nice update message for the commit and Pull Request
drush pm-updatestatus --security-only --format=csv | php /build-update-message.php > /update-message.txt

# Do the actual update of modules
drush pm-updatecode --security-only -y
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
[ $base_branch_or_tag != "master" ] && printf "\n\nImportant note: This update was created from a tag. Conflicts are expected in case \`master\` is ahead the tag. If that is the case, the conflicts should be manually fixed in a new branch" >> /update-message.txt

pull_request_url=$(php /create-pull-request.php -h $security_updates_branch < /update-message.txt)

echo "::set-output name=pull-request::$pull_request_url"
