#!/usr/bin/env bash

set -e

function printUsage() {
  echo "Usage: test.sh <repository> <username>"
  echo "Example: test.sh compucorp/rse davialexandre"
  echo "The script expects the following environment variables to be defined in order for it to run:"
  echo "  GITHUB_TOKEN: a personal access token from the given user with permissions to clone and create pull requests to the given repository"
  echo "  AWS_ACCESS_KEY: a access key with permission to read from the anonymized-db S3 bucket used by the mysql-anondb docker image"
  echo "  AWS_SECRET_KEY: the secret key for the given AWS_ACCESS_KEY"
}

function getContainerStatus() {
  docker inspect --format="{{if .Config.Healthcheck}}{{print .State.Health.Status}}{{end}}" "$1"
}

[ -z "$1" ] && echo "Missing repository!" && printUsage && exit 1
[ -z "$2" ] && echo "Missing username!" && printUsage && exit 1
[ -z "$GITHUB_TOKEN" ] && echo "Missing GITHUB_TOKEN" && printUsage && exit 1
[ -z "$AWS_ACCESS_KEY" ] && echo "Missing AWS_ACCESS_KEY" && printUsage && exit 1
[ -z "$AWS_SECRET_KEY" ] && echo "Missing AWS_ACCESS_KEY" && printUsage && exit 1

set -x

repository=$1
github_username=$2

## Clone the repository following an approach similar to what https://github.com/actions/checkout does
workdir="$PWD/workdir/$repository"
mkdir -p "$workdir"
cd "$workdir"
git init
git remote add origin "https://$github_username:$GITHUB_TOKEN@github.com/$repository"
git -c protocol.version=2 fetch --prune --progress --no-recurse-submodules origin "+refs/heads/*:refs/remotes/origin/*" "+refs/tags/*:refs/tags/*"
git checkout --progress --force -B master refs/remotes/origin/master

# We need the FROM_SITE in order to start the mysql-anondb container
from_site=$(grep -Eoh "FROM_SITE: (.+?)" "$workdir"/.github/workflows/* | cut -d ' ' -f 2)
[ -z "$from_site" ] \
  && echo "Couldn't extract the FROM SITE from the workflow file. Please check if this project has been configured for automated security updates" \
  && exit 1

# Some projects will need the PHP 5.6 of the action and some other will use 7.2
# (or others in the future), so we extract that from the workflow instead of
# hardcoding it on this script
action_docker_image=$(grep -Eoh "compucorp/drupal7-security-updates-action:.+?" "$workdir"/.github/workflows/*)
[ -z "$action_docker_image" ] \
  && echo "Couldn't find the docker image to run the security updates. Please check if this project has been configured for automated security updates" \
  && exit 1

# The action has a default value for the CIVICRM_ROOT variable, but this can be overridden in some projects
# The logic is to use the default value in the image, otherwise we use the custom one in the workflow
default_civicrm_root=$(docker inspect --format="{{range .Config.Env}}{{println .}}{{end}}" "$action_docker_image" | grep CIVICRM_ROOT | cut -d '=' -f 2)
action_civicrm_root=$(grep -Eoh "CIVICRM_ROOT: (.+?)" "$workdir"/.github/workflows/* | cut -d ' ' -f 2)
civicrm_root=${action_civicrm_root:-"$default_civicrm_root"}

run_id=$(echo "$repository" | tr "/" "_")_$(date +%Y%m%d%H%I%S)

# We'll be creating 2 containers. One for the database and one for the
# security update action. In order for them to be able to talk to each
# other, both need to be attached to the same network.
docker network create "$run_id"
docker run -d \
  --network "$run_id" \
  --name mysql \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=1 \
  -e FROM_SITE="$from_site" \
  -e S3_ACCESS_KEY="$AWS_ACCESS_KEY" \
  -e S3_SECRET_KEY="$AWS_SECRET_KEY" \
  -e ANONDB_S3_BUCKET=anonymized-dbs \
  compucorp/mysql-anondb

#Disable command tracing, to avoid printing the getContainerStatus in every cycle of the loop
set +x
echo "Waiting for the mysql container to become ready"
while [ "$(getContainerStatus "mysql")" = "starting" ];
do
  echo -n "."
  sleep 5
done

set -x

if [ "$(getContainerStatus "mysql")" = 'healthy' ];
then
  github_workspace="/github/workspace"
  docker run \
  --rm \
  --network "$run_id" \
  --workdir "$github_workspace" \
  -e GITHUB_TOKEN \
  -e GITHUB_WORKSPACE="$github_workspace" \
  -e GITHUB_ACTOR="$github_username" \
  -e GITHUB_REPOSITORY="$repository" \
  -e CIVICRM_ROOT="$civicrm_root" \
  -v "$workdir":"$github_workspace" \
  "$action_docker_image"
fi
