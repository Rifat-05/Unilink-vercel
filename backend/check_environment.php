<?php
$driver = strtolower((string)(getenv('DATA_DRIVER') ?: 'file'));
$drivers = PDO::getAvailableDrivers();
echo "PHP: " . PHP_VERSION . PHP_EOL;
echo "php.ini: " . (php_ini_loaded_file() ?: 'none') . PHP_EOL;
echo "UniLink data driver: {$driver}" . PHP_EOL;
echo "PDO drivers: " . ($drivers ? implode(', ', $drivers) : 'NONE') . PHP_EOL;
echo "pdo_mysql: " . (in_array('mysql', $drivers, true) ? 'OK' : 'MISSING') . PHP_EOL;
echo "fileinfo: " . (class_exists('finfo') ? 'OK' : 'MISSING (optional in file mode)') . PHP_EOL;
if ($driver === 'mysql' && !in_array('mysql', $drivers, true)) exit(1);
exit(PHP_VERSION_ID >= 80100 ? 0 : 1);
