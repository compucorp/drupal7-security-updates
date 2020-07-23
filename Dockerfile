FROM compucorp/civicrm-buildkit:latest

COPY entrypoint.sh /entrypoint.sh
COPY settings.php /settings.php
COPY build-update-message.php /build-update-message.php
COPY create-pull-request.php /create-pull-request.php

ENTRYPOINT ["/entrypoint.sh"]
