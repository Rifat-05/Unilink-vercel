<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set(
    'error_log',
    getenv('VERCEL') ? 'php://stderr' : __DIR__ . '/../storage/php-errors.log'
);

function json_response(mixed $data, int $status = 200): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');

    echo json_encode(
        $data,
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );

    exit;
}

function body(): array
{
    $type = strtolower((string)($_SERVER['CONTENT_TYPE'] ?? ''));

    if (str_contains($type, 'application/json')) {
        $raw = file_get_contents('php://input');

        if ($raw === false || trim($raw) === '') {
            return [];
        }

        $decoded = json_decode($raw, true);

        return is_array($decoded) ? $decoded : [];
    }

    return $_POST;
}

function require_method(string $method): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== $method) {
        json_response(['error' => 'Method not allowed'], 405);
    }
}

function id_param(string $key = 'id'): int
{
    $id = (int)($_GET[$key] ?? 0);

    if ($id < 1) {
        json_response(['error' => 'Invalid id'], 422);
    }

    return $id;
}

set_exception_handler(function (Throwable $e) {
    error_log((string)$e);

    json_response(
        ['error' => 'Unable to complete this request. Please try again.'],
        500
    );
});

if (!in_array(
    $_SERVER['REQUEST_METHOD'] ?? 'GET',
    ['GET', 'HEAD', 'OPTIONS'],
    true
)) {
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';

    if (
        $origin &&
        parse_url($origin, PHP_URL_HOST) !==
        explode(':', $_SERVER['HTTP_HOST'] ?? '')[0]
    ) {
        json_response(['error' => 'Invalid request origin'], 403);
    }

    if (($_SERVER['HTTP_SEC_FETCH_SITE'] ?? '') === 'cross-site') {
        json_response(['error' => 'Invalid request origin'], 403);
    }
}

$config = require __DIR__ . '/config.php';

if (
    ($config['resource_storage'] ?? 'file') === 'file' &&
    !is_dir($config['upload_dir'])
) {
    @mkdir($config['upload_dir'], 0750, true);
}

$pdoOptions = [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES => false,
];

if (defined('PDO::MYSQL_ATTR_SSL_CA')) {
    $caPath = (string)($config['ssl_ca_path'] ?? '');
    $caPem = (string)($config['ssl_ca'] ?? '');

    if ($caPem !== '') {
        $caPath =
            rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) .
            DIRECTORY_SEPARATOR .
            'unilink-db-ca.pem';

        $caPem = str_replace('\\n', "\n", $caPem);

        if (@file_put_contents($caPath, $caPem) === false) {
            throw new RuntimeException(
                'Unable to prepare database CA certificate'
            );
        }
    }

    if ($caPath !== '') {
        $pdoOptions[PDO::MYSQL_ATTR_SSL_CA] = $caPath;
    }
}

$pdo = new PDO(
    $config['dsn'],
    $config['user'],
    $config['password'],
    $pdoOptions
);

final class UniLinkDbSessionHandler implements SessionHandlerInterface
{
    public function __construct(private PDO $pdo)
    {
    }

    public function open(string $path, string $name): bool
    {
        return true;
    }

    public function close(): bool
    {
        return true;
    }

    public function read(string $id): string|false
    {
        $s = $this->pdo->prepare(
            'SELECT session_data
             FROM app_sessions
             WHERE session_id=?
             AND last_activity>=?'
        );

        $s->execute([
            $id,
            time() - (int)ini_get('session.gc_maxlifetime')
        ]);

        $v = $s->fetchColumn();

        return $v === false ? '' : (string)$v;
    }

    public function write(string $id, string $data): bool
    {
        $s = $this->pdo->prepare(
            'INSERT INTO app_sessions
                (session_id,session_data,last_activity)
             VALUES(?,?,?)
             ON DUPLICATE KEY UPDATE
                session_data=VALUES(session_data),
                last_activity=VALUES(last_activity)'
        );

        return $s->execute([
            $id,
            $data,
            time()
        ]);
    }

    public function destroy(string $id): bool
    {
        $s = $this->pdo->prepare(
            'DELETE FROM app_sessions WHERE session_id=?'
        );

        return $s->execute([$id]);
    }

    public function gc(int $max_lifetime): int|false
    {
        $s = $this->pdo->prepare(
            'DELETE FROM app_sessions WHERE last_activity<?'
        );

        $s->execute([
            time() - $max_lifetime
        ]);

        return $s->rowCount();
    }
}

if (session_status() !== PHP_SESSION_ACTIVE) {
    $secureCookie =
        !empty($_SERVER['HTTPS']) ||
        strtolower((string)(
            $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? ''
        )) === 'https';

    session_set_cookie_params([
        'httponly' => true,
        'secure' => $secureCookie,
        'samesite' => 'Lax',
        'path' => '/'
    ]);

    session_set_save_handler(
        new UniLinkDbSessionHandler($pdo),
        true
    );

    session_start();
}

function user(PDO $pdo): ?array
{
    if (empty($_SESSION['user_id'])) {
        return null;
    }

    $s = $pdo->prepare(
        "SELECT *
         FROM users
         WHERE user_id=?
         AND account_status='active'"
    );

    $s->execute([
        $_SESSION['user_id']
    ]);

    return $s->fetch() ?: null;
}

function require_user(PDO $pdo): array
{
    $u = user($pdo);

    if (!$u) {
        json_response(
            ['error' => 'Authentication required'],
            401
        );
    }

    return $u;
}

function require_role(array $u, array $roles): void
{
    if (!in_array(
        $u['account_type'],
        $roles,
        true
    )) {
        json_response(
            ['error' => 'Forbidden'],
            403
        );
    }
}

function audit(
    PDO $pdo,
    ?int $actor,
    string $action,
    string $type,
    ?int $id = null,
    ?array $details = null
): void {
    $s = $pdo->prepare(
        'INSERT INTO audit_logs
            (actor_id,action,entity_type,entity_id,details)
         VALUES(?,?,?,?,?)'
    );

    $s->execute([
        $actor,
        $action,
        $type,
        $id,
        $details ? json_encode($details) : null
    ]);
}
