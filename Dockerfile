ARG php_version=7.2
FROM compucorp/civicrm-buildkit:1.0.0-php${php_version}

ENV CIVICRM_ROOT sites/all/modules/civicrm

COPY [ "entrypoint.sh", "*.php", "/" ]

ENTRYPOINT ["/entrypoint.sh"]
