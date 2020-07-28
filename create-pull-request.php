<?php

/**
 * Small Utility script to help us creating a Pull Request using Github's Rest API.
 */

$user = getenv('GITHUB_ACTOR');
$token = getenv('GITHUB_TOKEN');
$repository = getenv('GITHUB_REPOSITORY');
$body = file_get_contents('php://stdin');

$opts = getopt('h:');

if (empty($opts['h'])) {
    throw new RuntimeException('Head branch not specified!');
}

if (empty($user)) {
    throw new RuntimeException('GITHUB_ACTOR not set!');
}

if (empty($token)) {
    throw new RuntimeException('GITHUB_TOKEN not set!');
}

if (empty($repository)) {
    throw new RuntimeException('GITHUB_REPOSITORY not set!');
}

if (empty($body)) {
    throw new RuntimeException('Update message empty!');
}

$head = $opts['h'];

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, "https://api.github.com/repos/$repository/pulls");
curl_setopt($ch, CURLOPT_POST, 1);
curl_setopt($ch, CURLOPT_USERAGENT, 'Drupal7-Security-Updates');
curl_setopt($ch, CURLOPT_USERPWD, "$user:$token");
curl_setopt(
    $ch,
    CURLOPT_POSTFIELDS,
    json_encode(
        [
            'title' => 'Automated Security Updates',
            'body' => $body,
            'head' => $head,
            'base' => 'master',
            'labels' => ['security update']
        ]
    )
);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$output = curl_exec($ch);
if ($output === false) {
    echo 'Curl error';
    echo curl_error($ch);
    curl_close($ch);

    exit(1);
}
curl_close($ch);
$output = json_decode($output, false);

if (empty($output)) {
    throw new RuntimeException('Empty Response!');
}

if (!empty($output->html_url)) {
    echo $output->html_url;
    exit();
}

/*
 * If there are any errors other than that the Pull Request already exists, we throw an error.
 *
 * It's not easy to check if a PR for a branch already exists, so, instead, we simply always
 * try to create one and ignore the error.
 */
if (!empty($output->errors)) {
    $repoOwner = explode('/', $repository)[0];
    foreach ($output->errors as $error) {
        if (empty($error->message)) {
            throw new RuntimeException('Unknown API error!');
        }
        if ($error->message !== "A pull request already exists for $repoOwner:$head.") {
            throw new RuntimeException('Error creating pull request: ' . $error->message);
        }
    }
}
