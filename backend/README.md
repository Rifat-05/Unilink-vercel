# UniLink PHP MVP backend

Use `../README_LAUNCH.md` for the fastest setup.

The backend is a same-origin PHP JSON API using PHP sessions and MySQL. The current core MVP supports registration/login/logout, profiles, feed posts, student search and connection requests, persistent direct messages, notifications, and protected resource upload/download.

For a clean classroom database, import `database/unilink_mvp.sql` or run:

```bash
php backend/setup_db.php
```

Run locally from the project root with:

```bash
php -S 127.0.0.1:8080 -t backend/public backend/public/index.php
```

`GET /api/health` should return `{"ok":true,...}` when PHP can connect to MySQL.
