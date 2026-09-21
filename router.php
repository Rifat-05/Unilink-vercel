<?php
// Apache/shared-hosting entry point. Normalize a subfolder install (for example
// /unilink/api/...) so the application router always receives /api/....
$scriptName = str_replace('\\', '/', (string)($_SERVER['SCRIPT_NAME'] ?? '/router.php'));
$base = rtrim(str_replace('\\', '/', dirname($scriptName)), '/.');
if ($base !== '' && $base !== '/' && isset($_SERVER['REQUEST_URI'])) {
    $uri = (string)$_SERVER['REQUEST_URI'];
    $parts = parse_url($uri);
    $path = (string)($parts['path'] ?? '');
    if ($path === $base || str_starts_with($path, $base . '/')) {
        $newPath = substr($path, strlen($base));
        if ($newPath === '') $newPath = '/';
        $_SERVER['REQUEST_URI'] = $newPath . (isset($parts['query']) ? '?' . $parts['query'] : '');
    }
}
require __DIR__ . '/backend/public/index.php';
