<?php
// Environment variables are preferred in production. Never commit real credentials.
// DATABASE_URL / MYSQL_URL can be used by managed MySQL providers. Explicit DB_*
// values take precedence when supplied.
$url = getenv('DATABASE_URL') ?: getenv('MYSQL_URL') ?: '';
$parsed = $url ? parse_url($url) : false;

$host = getenv('DB_HOST') ?: (($parsed && isset($parsed['host'])) ? $parsed['host'] : '127.0.0.1');
$port = getenv('DB_PORT') ?: (($parsed && isset($parsed['port'])) ? (string)$parsed['port'] : '3306');
$name = getenv('DB_NAME') ?: (($parsed && isset($parsed['path'])) ? ltrim((string)$parsed['path'], '/') : 'unilink');
$user = getenv('DB_USER') ?: (getenv('UNILINK_DB_USER') ?: (($parsed && isset($parsed['user'])) ? urldecode((string)$parsed['user']) : 'root'));
$password = getenv('DB_PASSWORD') ?: (getenv('UNILINK_DB_PASSWORD') ?: (($parsed && isset($parsed['pass'])) ? urldecode((string)$parsed['pass']) : ''));

$isVercel = getenv('VERCEL') !== false;
$maxUpload = (int)(getenv('MAX_UPLOAD_BYTES') ?: ($isVercel ? 4000000 : 25 * 1024 * 1024));
if ($maxUpload < 1) $maxUpload = 4000000;

return [
    'dsn' => getenv('UNILINK_DB_DSN') ?: "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4",
    'user' => $user,
    'password' => $password,
    'upload_dir' => __DIR__ . '/../storage/uploads',
    'upload_url' => '/storage/uploads',
    'max_upload_bytes' => $maxUpload,
    'resource_storage' => strtolower((string)(getenv('RESOURCE_STORAGE') ?: ($isVercel ? 'database' : 'file'))),
    'ssl_ca_path' => getenv('DB_SSL_CA_PATH') ?: '',
    'ssl_ca' => getenv('DB_SSL_CA') ?: '',
];
