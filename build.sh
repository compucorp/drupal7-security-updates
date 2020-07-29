#!/usr/bin/env bash

set -ex

[ -z "$1" ] && echo "Please pass the version number. Example: ./build.sh 1.0.1" && exit 1

image_name=compucorp/drupal7-security-updates-action
tag="$image_name:${1}"
php5_variant="${tag}-php5.6"
php7_variant="${tag}-php7.2"

docker build --build-arg php_version=5.6 -t "$php5_variant" .
docker build -t "$php7_variant" .
docker push $image_name
