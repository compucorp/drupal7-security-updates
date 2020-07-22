# Drupal 7 Security Updates Action

This is a [Docker based Github Action](https://docs.github.com/en/actions/creating-actions/creating-a-docker-container-action) 
which checks for available security updates for a Drupal 7 project. It downloads and pushes the updates to a separate branch, 
and creates a Pull Request so that the updates can be tested before being merged to `master`.

## Requirements

This action can only be used by workflows inside repositories with Drupal 7 projects following the [standard Drupal 7 
folder structure](https://compucorp.atlassian.net/wiki/spaces/SD/pages/84344881/Drupal+7+folder+structure).

It assumes it will be used in a workflow containing a service named `mysql`, which exposes a database named `drupal` 
containing a valid schema (anonymized or not) for the site in the workflow repo. We strongly recommend using 
[compucorp/mysql-anondb](https://github.com/compucorp/mysql-anondb-docker) for that.

Since the action includes some logic based on the existence of tags and branches, it cannot be used in a shallow clone. 
Make sure of adding `fetch-depth: 0` to your step reponsible for checking out the code.

## Usage

Here is an example of how to use it inside a Github Action workflow:

```yaml
name: Security Updates
on: push

jobs:
  main:
    runs-on: ubuntu-latest

    services:
      mysql:
        image: compucorp/mysql-anondb
        ports:
          - 3306:3306
        env:
          FROM_SITE: crm.world-heart-federation.org
          MYSQL_ALLOW_EMPTY_PASSWORD: yes
          S3_ACCESS_KEY: ${{ secrets.ANONDB_S3_ACCESS_KEY }}
          S3_SECRET_KEY: ${{ secrets.ANONDB_S3_SECRET_KEY }}
          DRUPAL_ONLY: yes
          ANONDB_S3_BUCKET: anonymized-dbs

    steps:
      - uses: actions/checkout@v2
        with:
          fetch-depth: 0 #No shallow clones!

      - name: Security updates
        id: security-updates
        uses: compucorp/drupal7-security-updates@v1.0.0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

The action will always consider the latest tag as the base for security updates. This is based on the assumption that 
this is what we're running in production. If for some reason it cannot find any tags, the `master` branch will be used 
instead.

If there are security updates available, they will be pushed to a branch named `<tag or master>_security_updates`. A 
Pull Request will also be created targetting `master`. Both the commit and the Pull Request will contain a list of all 
the modules which have been updated, including their current version and the version they have been updated to.

## Notifying about updates

The action isn't responsible for any kind of notification itself, but it exposes 2 outputs (`branch` and `pull-request`), 
which you can use in subsequent steps to notify people about the updates. Here's an example of sending notifications via 
Slack:

```yaml
- name: Send slack notification
  uses: rtCamp/action-slack-notify@v2.1.0
  if: ${{ steps.security-update.outputs.branch != '' }}
  env:
    SLACK_COLOR: '#ff0000'
    SLACK_ICON: https://avatars.slack-edge.com/2020-07-20/1252089680691_0b8e8db7fc49764710a0_48.jpg
    MSG_MINIMAL: true
    SLACK_USERNAME: Security Updates
    SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
    SLACK_TITLE: Drupal 7 Security Updates
    SLACK_MESSAGE: |
      :warning: *There are new security updates available for <<SITE>>* :warning:

      The updates have been applied to the `${{ steps.security-updates.outputs.branch }}` branch.

      For more details on what has been updated, check the Pull Request: ${{ steps.security-updates.outputs.pull-request }}
```

Note that in order to be able to access the output of a step, you need to give it an `id` (`security-updates` in this 
case). Also note that `branch` will be empty in case no security updates were applied. We can use that inside an `if` 
and avoid sending the notification in case nothing was updated.
