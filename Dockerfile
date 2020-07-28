FROM compucorp/civicrm-buildkit:1.0.0-php5.6

COPY entrypoint.sh /entrypoint.sh
COPY settings.php /settings.php
COPY build-update-message.php /build-update-message.php
COPY create-pull-request.php /create-pull-request.php

ENTRYPOINT ["/entrypoint.sh"]
