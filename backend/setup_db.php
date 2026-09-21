<?php
declare(strict_types=1);
$config = require __DIR__ . '/config.php';
$host = getenv('DB_HOST') ?: '127.0.0.1';
$port = getenv('DB_PORT') ?: '3306';
$name = getenv('DB_NAME') ?: 'unilink';
$user = getenv('DB_USER') ?: (getenv('UNILINK_DB_USER') ?: 'root');
$password = getenv('DB_PASSWORD') ?: (getenv('UNILINK_DB_PASSWORD') ?: '');
if (!preg_match('/^[A-Za-z0-9_]+$/', $name)) { fwrite(STDERR, "Invalid DB_NAME\n"); exit(1); }
try {
    $pdo = new PDO("mysql:host={$host};port={$port};charset=utf8mb4", $user, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_EMULATE_PREPARES => true,
    ]);
    $sql = file_get_contents(dirname(__DIR__) . '/database/unilink_mvp.sql');
    if ($sql === false) throw new RuntimeException('Could not read database/unilink_mvp.sql');
    foreach (preg_split('/;\s*(?:\r?\n|$)/', $sql) as $statement) {
        $statement = trim($statement);
        if ($statement === '' || preg_match('/^--/', $statement)) {
            // Strip leading line comments, but keep any SQL that follows them.
            $statement = preg_replace('/^(?:--[^\n]*\n\s*)+/', '', $statement);
        }
        if (trim((string)$statement) !== '') $pdo->exec($statement);
    }
    $check = new PDO($config['dsn'], $config['user'], $config['password'], [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
    $count = (int)$check->query('SELECT COUNT(*) FROM universities')->fetchColumn();
    echo "UniLink MVP database is ready. Universities: {$count}\n";
} catch (Throwable $e) {
    fwrite(STDERR, "Database setup failed: {$e->getMessage()}\n");
    exit(1);
}
