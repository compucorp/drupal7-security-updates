<?php

/**
 * This script builds a commit/pr message based on the output of
 * drush pm-updatestatus --security-only --format=csv 2> /dev/null
 */

$handle = fopen('php://stdin', 'rb');

if ($handle === false) {
    exit;
}

$updates = [];
while (($data = fgetcsv($handle, 1000, ",")) !== false) {
    // Basic validation.
    // If the input doesn't contain 4 fields, we just stop processing it
    if (count($data) !== 4) {
        exit;
    }
    $updates[] = $data;
}
fclose($handle);

if (empty($updates)) {
    exit;
}

$message = 'This includes the following updates:' . PHP_EOL;

foreach ($updates as $update) {
    $message .= sprintf(
        '- %s from version %s to [%s](https://www.drupal.org/project/%s/releases/%s)',
        $update[0],
        $update[1],
        $update[2],
        $update[0],
        $update[2]
    );
    $message .= PHP_EOL;
}

echo $message;
