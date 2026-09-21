<?php
declare(strict_types=1);

$path = parse_url(
    $_SERVER['REQUEST_URI'] ?? '/',
    PHP_URL_PATH
) ?: '/';

// Serve static frontend pages/assets.
if (!str_starts_with($path, '/api/')) {

    if ($path === '/') {
        $path = '/index.html';
    }

    $root = realpath(
        dirname(__DIR__, 2)
    );

    $allowed =
        preg_match(
            '#^/[a-zA-Z0-9_-]+\.html$#',
            $path
        ) ||
        preg_match(
            '#^/assets/[a-zA-Z0-9_./-]+\.(js|css|png|jpg|jpeg|webp|svg|ico)$#',
            $path
        );

    if ($allowed && $root) {

        $file = realpath(
            $root . $path
        );

        if (
            $file &&
            str_starts_with(
                $file,
                $root . DIRECTORY_SEPARATOR
            ) &&
            is_file($file)
        ) {

            $types = [
                'html' => 'text/html; charset=utf-8',
                'js' => 'text/javascript; charset=utf-8',
                'css' => 'text/css; charset=utf-8',
                'png' => 'image/png',
                'jpg' => 'image/jpeg',
                'jpeg' => 'image/jpeg',
                'webp' => 'image/webp',
                'svg' => 'image/svg+xml',
                'ico' => 'image/x-icon'
            ];

            header(
                'Content-Type: ' .
                (
                    $types[
                        strtolower(
                            pathinfo(
                                $file,
                                PATHINFO_EXTENSION
                            )
                        )
                    ] ??
                    'application/octet-stream'
                )
            );

            readfile($file);
            exit;
        }
    }

    http_response_code(404);
    exit('Not found');
}

// Load config without opening DB first.
require dirname(__DIR__) . '/config.php';

$driver = strtolower(
    (string)(
        getenv('DATA_DRIVER') ?:
        (
            getenv('VERCEL')
                ? 'mysql'
                : 'file'
        )
    )
);

$hasMysql = in_array(
    'mysql',
    PDO::getAvailableDrivers(),
    true
);

if (
    $driver === 'file' ||
    (
        $driver === 'auto' &&
        !$hasMysql
    )
) {
    require __DIR__ . '/index_file.php';
    exit;
}

require dirname(__DIR__) . '/bootstrap.php';

$method =
    $_SERVER['REQUEST_METHOD'] ??
    'GET';

function notify_user(
    PDO $pdo,
    int $userId,
    string $type,
    string $title,
    ?string $body = null,
    ?string $target = null
): void {
    try {
        $s = $pdo->prepare(
            'INSERT INTO notifications
                (user_id,notification_type,title,body,target_path)
             VALUES(?,?,?,?,?)'
        );

        $s->execute([
            $userId,
            $type,
            $title,
            $body,
            $target
        ]);

    } catch (Throwable $e) {

        // Notification errors must never break
        // the main user action.
        error_log(
            'notification: ' .
            $e->getMessage()
        );
    }
}

// ---------------------------------------------------------
// Health
// ---------------------------------------------------------

if (
    $path === '/api/health' &&
    $method === 'GET'
) {
    $pdo->query('SELECT 1');

    json_response([
        'ok' => true,
        'database' => 'connected',
        'time' => gmdate('c')
    ]);
}

// ---------------------------------------------------------
// Registration
// ---------------------------------------------------------

if (
    $path === '/api/auth/register' &&
    $method === 'POST'
) {

    $b = body();

    foreach (
        [
            'full_name',
            'email',
            'password',
            'student_id',
            'department'
        ] as $k
    ) {
        if (
            trim(
                (string)($b[$k] ?? '')
            ) === ''
        ) {
            json_response([
                'error' => "$k is required"
            ], 422);
        }
    }

    $name = trim(
        (string)$b['full_name']
    );

    $email = strtolower(
        trim(
            (string)$b['email']
        )
    );

    $password =
        (string)$b['password'];

    $studentId = trim(
        (string)$b['student_id']
    );

    $department = trim(
        (string)$b['department']
    );

    if (
        strlen($name) < 2 ||
        strlen($name) > 150
    ) {
        json_response([
            'error' =>
                'Enter a valid full name'
        ], 422);
    }

    if (
        !filter_var(
            $email,
            FILTER_VALIDATE_EMAIL
        )
    ) {
        json_response([
            'error' =>
                'Enter a valid email address'
        ], 422);
    }

    if (
        strlen($password) < 8
    ) {
        json_response([
            'error' =>
                'Password must be at least 8 characters'
        ], 422);
    }

    if (
        strlen($studentId) > 50 ||
        strlen($department) > 100
    ) {
        json_response([
            'error' =>
                'Student ID or department is too long'
        ], 422);
    }

    $universityId = (int)(
        $b['university_id'] ??
        0
    );

    if (
        $universityId < 1 &&
        !empty(
            $b['university_name']
        )
    ) {

        $s = $pdo->prepare(
            "SELECT university_id
             FROM universities
             WHERE name=?
             AND status='active'
             LIMIT 1"
        );

        $s->execute([
            trim(
                (string)$b[
                    'university_name'
                ]
            )
        ]);

        $universityId =
            (int)(
                $s->fetchColumn() ?:
                0
            );
    }

    if ($universityId < 1) {
        json_response([
            'error' =>
                'Choose a valid university'
        ], 422);
    }

    $s = $pdo->prepare(
        "SELECT university_id
         FROM universities
         WHERE university_id=?
         AND status='active'"
    );

    $s->execute([
        $universityId
    ]);

    if (
        !$s->fetchColumn()
    ) {
        json_response([
            'error' =>
                'Choose a valid university'
        ], 422);
    }

    $pdo->beginTransaction();

    try {

        $s = $pdo->prepare(
            "INSERT INTO users
                (
                    full_name,
                    email,
                    password_hash,
                    account_type,
                    account_status,
                    email_verified,
                    terms_accepted_at
                )
             VALUES(
                ?,
                ?,
                ?,
                'student',
                'active',
                0,
                NOW()
             )"
        );

        $s->execute([
            $name,
            $email,
            password_hash(
                $password,
                PASSWORD_DEFAULT
            )
        ]);

        $uid =
            (int)$pdo->lastInsertId();

        $s = $pdo->prepare(
            'INSERT INTO student_profiles
                (
                    user_id,
                    university_id,
                    student_id,
                    department,
                    semester
                )
             VALUES(?,?,?,?,?)'
        );

        $s->execute([
            $uid,
            $universityId,
            $studentId,
            $department,
            trim(
                (string)(
                    $b['semester'] ??
                    ''
                )
            ) ?: null
        ]);

        $pdo->commit();

        json_response([
            'message' =>
                'Registration successful',
            'user_id' =>
                $uid
        ], 201);

    } catch (Throwable $e) {

        if (
            $pdo->inTransaction()
        ) {
            $pdo->rollBack();
        }

        if (
            $e instanceof PDOException &&
            (
                (
                    $e->errorInfo[1] ??
                    null
                ) === 1062
            )
        ) {
            json_response([
                'error' =>
                    'That email or student ID is already registered'
            ], 409);
        }

        throw $e;
    }
}

// ---------------------------------------------------------
// Login
// ---------------------------------------------------------

if (
    $path === '/api/auth/login' &&
    $method === 'POST'
) {

    $b = body();

    $email = strtolower(
        trim(
            (string)(
                $b['email'] ??
                ''
            )
        )
    );

    $password =
        (string)(
            $b['password'] ??
            ''
        );

    if (
        $email === '' ||
        $password === ''
    ) {
        json_response([
            'error' =>
                'Email and password are required'
        ], 422);
    }

    $s = $pdo->prepare(
        'SELECT *
         FROM users
         WHERE email=?
         LIMIT 1'
    );

    $s->execute([
        $email
    ]);

    $u = $s->fetch();

    if (
        !$u ||
        !password_verify(
            $password,
            $u['password_hash']
        ) ||
        $u['account_status'] !==
        'active'
    ) {
        json_response([
            'error' =>
                'Invalid email or password'
        ], 401);
    }

    session_regenerate_id(true);

    $_SESSION['user_id'] =
        (int)$u['user_id'];

    $pdo->prepare(
        'UPDATE users
         SET last_seen_at=NOW()
         WHERE user_id=?'
    )->execute([
        $u['user_id']
    ]);

    unset(
        $u['password_hash']
    );

    json_response([
        'user' => $u
    ]);
}

// ---------------------------------------------------------
// Logout
// ---------------------------------------------------------

if (
    $path === '/api/auth/logout' &&
    $method === 'POST'
) {

    $_SESSION = [];

    $params =
        session_get_cookie_params();

    setcookie(
        session_name(),
        '',
        [
            'expires' =>
                time() - 3600,

            'path' =>
                $params['path'] ?:
                '/',

            'domain' =>
                $params['domain'] ?:
                '',

            'secure' =>
                (bool)$params[
                    'secure'
                ],

            'httponly' =>
                true,

            'samesite' =>
                'Lax'
        ]
    );

    session_destroy();

    json_response([
        'message' =>
            'Logged out'
    ]);
}

// ---------------------------------------------------------
// Current logged-in user
// ---------------------------------------------------------

if (
    $path === '/api/auth/me' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    unset(
        $u['password_hash']
    );

    json_response([
        'user' => $u
    ]);
}

// ---------------------------------------------------------
// Profile
// ---------------------------------------------------------

if (
    $path === '/api/profile' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $s = $pdo->prepare(
        'SELECT
            u.user_id,
            u.full_name,
            u.email,
            u.account_type,
            sp.*
         FROM users u
         LEFT JOIN student_profiles sp
         ON sp.user_id=u.user_id
         WHERE u.user_id=?'
    );

    $s->execute([
        $u['user_id']
    ]);

    json_response([
        'profile' =>
            $s->fetch()
    ]);
}

if (
    $path === '/api/profile' &&
    in_array(
        $method,
        ['PUT', 'PATCH'],
        true
    )
) {

    $u =
        require_user($pdo);

    $b =
        body();

    $allowed = [
        'bio',
        'location',
        'github_url',
        'linkedin_url',
        'portfolio_url',
        'semester',
        'department'
    ];

    $sets = [];
    $vals = [];

    foreach (
        $allowed as $k
    ) {

        if (
            array_key_exists(
                $k,
                $b
            )
        ) {

            $sets[] =
                "$k=?";

            $vals[] =
                trim(
                    (string)$b[$k]
                ) ?: null;
        }
    }

    if (!$sets) {
        json_response([
            'error' =>
                'No editable fields supplied'
        ], 422);
    }

    $vals[] =
        $u['user_id'];

    $pdo->prepare(
        'UPDATE student_profiles
         SET ' .
        implode(',', $sets) .
        ' WHERE user_id=?'
    )->execute(
        $vals
    );

    json_response([
        'message' =>
            'Profile updated'
    ]);
}

// ---------------------------------------------------------
// Feed posts
// ---------------------------------------------------------

if (
    $path === '/api/posts' &&
    $method === 'GET'
) {

    require_user($pdo);

    $s = $pdo->query(
        'SELECT
            p.post_id,
            p.content,
            p.created_at,
            u.user_id author_id,
            u.full_name author_name
         FROM posts p
         JOIN users u
         ON u.user_id=p.author_id
         ORDER BY
            p.created_at DESC,
            p.post_id DESC
         LIMIT 100'
    );

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

if (
    $path === '/api/posts' &&
    $method === 'POST'
) {

    $u =
        require_user($pdo);

    $b =
        body();

    $content =
        trim(
            (string)(
                $b['content'] ??
                ''
            )
        );

    if ($content === '') {
        json_response([
            'error' =>
                'Post cannot be empty'
        ], 422);
    }

    if (
        strlen($content) >
        5000
    ) {
        json_response([
            'error' =>
                'Post is too long'
        ], 422);
    }

    $s =
        $pdo->prepare(
            'INSERT INTO posts
                (author_id,content)
             VALUES(?,?)'
        );

    $s->execute([
        $u['user_id'],
        $content
    ]);

    json_response([
        'post_id' =>
            (int)$pdo
                ->lastInsertId()
    ], 201);
}

// ---------------------------------------------------------
// Study partner search
// ---------------------------------------------------------

if (
    $path === '/api/users/search' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $term =
        trim(
            (string)(
                $_GET['q'] ??
                ''
            )
        );

    $q =
        '%' . $term . '%';

    $s = $pdo->prepare(
        "SELECT
            u.user_id,
            u.full_name,
            sp.student_id,
            sp.department,
            sp.semester,
            sp.bio
         FROM users u
         JOIN student_profiles sp
         ON sp.user_id=u.user_id
         WHERE u.user_id<>?
         AND u.account_type='student'
         AND u.account_status='active'
         AND (
            u.full_name LIKE ?
            OR sp.student_id LIKE ?
            OR sp.department LIKE ?
         )
         ORDER BY u.full_name
         LIMIT 50"
    );

    $s->execute([
        $u['user_id'],
        $q,
        $q,
        $q
    ]);

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

// ---------------------------------------------------------
// Send connection request
// ---------------------------------------------------------

if (
    $path ===
    '/api/connections/request' &&
    $method === 'POST'
) {

    $u =
        require_user($pdo);

    $b =
        body();

    $to = (int)(
        $b['user_id'] ??
        $b['receiver_id'] ??
        0
    );

    if (
        $to < 1 ||
        $to ===
        (int)$u['user_id']
    ) {
        json_response([
            'error' =>
                'Invalid connection target'
        ], 422);
    }

    $check = $pdo->prepare(
        "SELECT
            user_id,
            full_name
         FROM users
         WHERE user_id=?
         AND account_type='student'
         AND account_status='active'"
    );

    $check->execute([
        $to
    ]);

    $target =
        $check->fetch();

    if (!$target) {
        json_response([
            'error' =>
                'Student not found'
        ], 404);
    }

    $check = $pdo->prepare(
        "SELECT status
         FROM study_partner_requests
         WHERE (
            (sender_id=? AND receiver_id=?)
            OR
            (sender_id=? AND receiver_id=?)
         )
         AND status IN(
            'pending',
            'accepted'
         )
         ORDER BY request_id DESC
         LIMIT 1"
    );

    $check->execute([
        $u['user_id'],
        $to,
        $to,
        $u['user_id']
    ]);

    $existing =
        $check->fetchColumn();

    if (
        $existing ===
        'accepted'
    ) {
        json_response([
            'error' =>
                'You are already connected'
        ], 409);
    }

    if (
        $existing ===
        'pending'
    ) {
        json_response([
            'error' =>
                'A connection request is already pending'
        ], 409);
    }

    $s = $pdo->prepare(
        'INSERT INTO study_partner_requests
            (
                sender_id,
                receiver_id,
                message
            )
         VALUES(?,?,?)'
    );

    $s->execute([
        $u['user_id'],
        $to,
        trim(
            (string)(
                $b['message'] ??
                ''
            )
        ) ?: null
    ]);

    notify_user(
        $pdo,
        $to,
        'connection_request',
        'New study partner request',
        $u['full_name'] .
        ' wants to connect with you.',
        '/unilink-study-partners.html'
    );

    json_response([
        'request_id' =>
            (int)$pdo
                ->lastInsertId()
    ], 201);
}

// ---------------------------------------------------------
// Incoming requests
// ---------------------------------------------------------

if (
    $path ===
    '/api/connections/requests' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $s = $pdo->prepare(
        "SELECT
            r.request_id,
            r.sender_id,
            r.message,
            r.status,
            r.created_at,
            u.full_name sender_name
         FROM study_partner_requests r
         JOIN users u
         ON u.user_id=r.sender_id
         WHERE r.receiver_id=?
         AND r.status='pending'
         ORDER BY r.created_at DESC"
    );

    $s->execute([
        $u['user_id']
    ]);

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

// ---------------------------------------------------------
// Accept / reject request
// ---------------------------------------------------------

if (
    preg_match(
        '#^/api/connections/(\d+)$#',
        $path,
        $m
    ) &&
    $method === 'PATCH'
) {

    $u =
        require_user($pdo);

    $b =
        body();

    $status =
        in_array(
            $b['status'] ?? '',
            [
                'accepted',
                'declined'
            ],
            true
        )
            ? $b['status']
            : '';

    if (!$status) {
        json_response([
            'error' =>
                'Invalid status'
        ], 422);
    }

    $s = $pdo->prepare(
        "SELECT sender_id
         FROM study_partner_requests
         WHERE request_id=?
         AND receiver_id=?
         AND status='pending'"
    );

    $s->execute([
        (int)$m[1],
        $u['user_id']
    ]);

    $sender =
        (int)(
            $s->fetchColumn() ?:
            0
        );

    if (!$sender) {
        json_response([
            'error' =>
                'Request not found'
        ], 404);
    }

    $pdo->prepare(
        'UPDATE study_partner_requests
         SET status=?
         WHERE request_id=?'
    )->execute([
        $status,
        (int)$m[1]
    ]);

    if (
        $status ===
        'accepted'
    ) {

        notify_user(
            $pdo,
            $sender,
            'connection_accepted',
            'Study partner request accepted',
            $u['full_name'] .
            ' accepted your request.',
            '/unilink-study-partners.html'
        );
    }

    json_response([
        'updated' => 1
    ]);
}

// ---------------------------------------------------------
// Accepted connections
// ---------------------------------------------------------

if (
    $path ===
    '/api/connections' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $s = $pdo->prepare(
        "SELECT
            r.request_id,
            CASE
                WHEN r.sender_id=?
                THEN r.receiver_id
                ELSE r.sender_id
            END user_id,
            u.full_name,
            r.status
         FROM study_partner_requests r
         JOIN users u
         ON u.user_id=
            CASE
                WHEN r.sender_id=?
                THEN r.receiver_id
                ELSE r.sender_id
            END
         WHERE (
            r.sender_id=?
            OR r.receiver_id=?
         )
         AND r.status='accepted'
         ORDER BY u.full_name"
    );

    $s->execute([
        $u['user_id'],
        $u['user_id'],
        $u['user_id'],
        $u['user_id']
    ]);

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

// ---------------------------------------------------------
// Conversations
// ---------------------------------------------------------

if (
    $path ===
    '/api/conversations' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $s = $pdo->prepare(
        'SELECT
            c.conversation_id,
            c.created_at,
            CASE
                WHEN c.user_one_id=?
                THEN c.user_two_id
                ELSE c.user_one_id
            END participant_id,
            CASE
                WHEN c.user_one_id=?
                THEN u2.full_name
                ELSE u1.full_name
            END participant_name
         FROM direct_conversations c
         JOIN users u1
         ON u1.user_id=c.user_one_id
         JOIN users u2
         ON u2.user_id=c.user_two_id
         WHERE c.user_one_id=?
         OR c.user_two_id=?
         ORDER BY c.created_at DESC'
    );

    $s->execute([
        $u['user_id'],
        $u['user_id'],
        $u['user_id'],
        $u['user_id']
    ]);

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

if (
    $path ===
    '/api/conversations' &&
    $method === 'POST'
) {

    $u =
        require_user($pdo);

    $b =
        body();

    $other =
        (int)(
            $b['user_id'] ??
            0
        );

    if (
        $other < 1 ||
        $other ===
        (int)$u['user_id']
    ) {
        json_response([
            'error' =>
                'Invalid participant'
        ], 422);
    }

    $s = $pdo->prepare(
        "SELECT user_id
         FROM users
         WHERE user_id=?
         AND account_status='active'"
    );

    $s->execute([
        $other
    ]);

    if (
        !$s->fetchColumn()
    ) {
        json_response([
            'error' =>
                'User not found'
        ], 404);
    }

    $a = min(
        (int)$u['user_id'],
        $other
    );

    $z = max(
        (int)$u['user_id'],
        $other
    );

    $s = $pdo->prepare(
        'INSERT INTO direct_conversations
            (
                user_one_id,
                user_two_id
            )
         VALUES(?,?)
         ON DUPLICATE KEY UPDATE
            conversation_id=
            LAST_INSERT_ID(
                conversation_id
            )'
    );

    $s->execute([
        $a,
        $z
    ]);

    json_response([
        'conversation_id' =>
            (int)$pdo
                ->lastInsertId()
    ], 201);
}

// ---------------------------------------------------------
// Get conversation messages
// ---------------------------------------------------------

if (
    preg_match(
        '#^/api/conversations/(\d+)/messages$#',
        $path,
        $m
    ) &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $cid =
        (int)$m[1];

    $s = $pdo->prepare(
        'SELECT
            m.message_id,
            m.conversation_id,
            m.sender_id,
            m.body,
            m.delivered_at,
            m.read_at,
            m.created_at,
            u.full_name sender_name
         FROM direct_messages m
         JOIN direct_conversations c
         ON c.conversation_id=
            m.conversation_id
         JOIN users u
         ON u.user_id=
            m.sender_id
         WHERE m.conversation_id=?
         AND (
            c.user_one_id=?
            OR c.user_two_id=?
         )
         ORDER BY
            m.created_at,
            m.message_id'
    );

    $s->execute([
        $cid,
        $u['user_id'],
        $u['user_id']
    ]);

    $items =
        $s->fetchAll();

    $pdo->prepare(
        'UPDATE direct_messages
         SET read_at=
            COALESCE(
                read_at,
                NOW()
            )
         WHERE conversation_id=?
         AND sender_id<>?'
    )->execute([
        $cid,
        $u['user_id']
    ]);

    json_response([
        'items' => $items
    ]);
}

// ---------------------------------------------------------
// Send message
// ---------------------------------------------------------

if (
    preg_match(
        '#^/api/conversations/(\d+)/messages$#',
        $path,
        $m
    ) &&
    $method === 'POST'
) {

    $u =
        require_user($pdo);

    $b =
        body();

    $cid =
        (int)$m[1];

    $text =
        trim(
            (string)(
                $b['body'] ??
                ''
            )
        );

    if ($text === '') {
        json_response([
            'error' =>
                'Message is required'
        ], 422);
    }

    if (
        strlen($text) >
        10000
    ) {
        json_response([
            'error' =>
                'Message is too long'
        ], 422);
    }

    $s = $pdo->prepare(
        'SELECT
            user_one_id,
            user_two_id
         FROM direct_conversations
         WHERE conversation_id=?
         AND (
            user_one_id=?
            OR user_two_id=?
         )'
    );

    $s->execute([
        $cid,
        $u['user_id'],
        $u['user_id']
    ]);

    $conv =
        $s->fetch();

    if (!$conv) {
        json_response([
            'error' =>
                'Conversation not found'
        ], 404);
    }

    $s = $pdo->prepare(
        'INSERT INTO direct_messages
            (
                conversation_id,
                sender_id,
                body,
                delivered_at
            )
         VALUES(
            ?,
            ?,
            ?,
            NOW()
         )'
    );

    $s->execute([
        $cid,
        $u['user_id'],
        $text
    ]);

    $recipient =
        (
            (int)$conv['user_one_id'] ===
            (int)$u['user_id']
        )
            ? (int)$conv['user_two_id']
            : (int)$conv['user_one_id'];

    notify_user(
        $pdo,
        $recipient,
        'message',
        'New message from ' .
        $u['full_name'],
        substr(
            $text,
            0,
            160
        ),
        '/unilink_direct_messaging.html?conversation=' .
        $cid
    );

    json_response([
        'message_id' =>
            (int)$pdo
                ->lastInsertId()
    ], 201);
}

// ---------------------------------------------------------
// Resources list
// ---------------------------------------------------------

if (
    $path ===
    '/api/resources' &&
    $method === 'GET'
) {

    require_user($pdo);

    $q =
        trim(
            (string)(
                $_GET['q'] ??
                ''
            )
        );

    $like =
        "%$q%";

    $s = $pdo->prepare(
        "SELECT
            r.resource_id,
            r.title,
            r.resource_type,
            r.description,
            r.original_file_name,
            r.mime_type,
            r.file_size,
            r.download_count,
            r.created_at,
            c.course_code,
            c.course_name,
            u.full_name uploader
         FROM resources r
         JOIN courses c
         ON c.course_id=
            r.course_id
         JOIN users u
         ON u.user_id=
            r.uploaded_by
         WHERE r.status='active'
         AND (
            r.title LIKE ?
            OR c.course_code LIKE ?
            OR u.full_name LIKE ?
         )
         ORDER BY
            r.created_at DESC,
            r.resource_id DESC
         LIMIT 100"
    );

    $s->execute([
        $like,
        $like,
        $like
    ]);

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

// ---------------------------------------------------------
// Resource upload
// ---------------------------------------------------------

if (
    $path ===
    '/api/resources' &&
    $method === 'POST'
) {

    $u =
        require_user($pdo);

    if (
        !isset(
            $_FILES['file']
        )
    ) {
        json_response([
            'error' =>
                'Choose a file to upload'
        ], 422);
    }

    $f =
        $_FILES['file'];

    if (
        (
            $f['error'] ??
            UPLOAD_ERR_NO_FILE
        ) !==
        UPLOAD_ERR_OK
    ) {
        json_response([
            'error' =>
                'The upload failed. Please choose the file again'
        ], 422);
    }

    if (
        ($f['size'] ?? 0) < 1 ||
        $f['size'] >
        $config[
            'max_upload_bytes'
        ]
    ) {
        json_response([
            'error' =>
                'File must be between 1 byte and 25 MB'
        ], 422);
    }

    $title =
        trim(
            (string)(
                $_POST['title'] ??
                ''
            )
        );

    if ($title === '') {
        json_response([
            'error' =>
                'Resource title is required'
        ], 422);
    }

    if (
        !is_uploaded_file(
            $f['tmp_name']
        )
    ) {
        json_response([
            'error' =>
                'Invalid upload'
        ], 422);
    }

    $ext =
        strtolower(
            pathinfo(
                (string)$f['name'],
                PATHINFO_EXTENSION
            )
        );

    $allowedExt = [
        'pdf',
        'docx',
        'pptx'
    ];

    if (
        !in_array(
            $ext,
            $allowedExt,
            true
        )
    ) {
        json_response([
            'error' =>
                'Only PDF, DOCX and PPTX files are allowed'
        ], 422);
    }

    if (
        !class_exists('finfo')
    ) {
        json_response([
            'error' =>
                'Server fileinfo extension is not enabled'
        ], 500);
    }

    $fi =
        new finfo(
            FILEINFO_MIME_TYPE
        );

    $mime =
        (string)$fi->file(
            $f['tmp_name']
        );

    $validMime =
        $ext === 'pdf'
            ? [
                'application/pdf'
            ]
            : [
                'application/zip',
                'application/octet-stream',
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                'application/vnd.openxmlformats-officedocument.presentationml.presentation'
            ];

    if (
        !in_array(
            $mime,
            $validMime,
            true
        )
    ) {
        json_response([
            'error' =>
                'The selected file does not match its extension'
        ], 422);
    }

    $courseId =
        (int)(
            $_POST['course_id'] ??
            0
        );

    if ($courseId < 1) {

        $s = $pdo->prepare(
            "SELECT c.course_id
             FROM courses c
             JOIN student_profiles sp
             ON sp.university_id=
                c.university_id
             WHERE sp.user_id=?
             ORDER BY
                (
                    c.course_code='GENERAL'
                ) DESC,
                c.course_id
             LIMIT 1"
        );

        $s->execute([
            $u['user_id']
        ]);

        $courseId =
            (int)(
                $s->fetchColumn() ?:
                0
            );
    }

    if ($courseId < 1) {
        json_response([
            'error' =>
                'No course is configured for your university'
        ], 422);
    }

    $description =
        trim(
            (string)(
                $_POST[
                    'description'
                ] ??
                ''
            )
        ) ?: null;

    if (
        (
            $config[
                'resource_storage'
            ] ??
            'file'
        ) ===
        'database'
    ) {

        $blob =
            file_get_contents(
                $f['tmp_name']
            );

        if ($blob === false) {
            json_response([
                'error' =>
                    'Server could not read the uploaded file'
            ], 500);
        }

        $s = $pdo->prepare(
            "INSERT INTO resources
                (
                    uploaded_by,
                    course_id,
                    title,
                    resource_type,
                    description,
                    file_url,
                    original_file_name,
                    mime_type,
                    file_size,
                    file_data,
                    status
                )
             VALUES(
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                'active'
             )"
        );

        $s->bindValue(
            1,
            (int)$u['user_id'],
            PDO::PARAM_INT
        );

        $s->bindValue(
            2,
            $courseId,
            PDO::PARAM_INT
        );

        $s->bindValue(
            3,
            $title
        );

        $s->bindValue(
            4,
            'notes'
        );

        $s->bindValue(
            5,
            $description
        );

        $s->bindValue(
            6,
            'database'
        );

        $s->bindValue(
            7,
            (string)$f['name']
        );

        $s->bindValue(
            8,
            $mime
        );

        $s->bindValue(
            9,
            (int)$f['size'],
            PDO::PARAM_INT
        );

        $s->bindValue(
            10,
            $blob,
            PDO::PARAM_LOB
        );

        $s->execute();

        $rid =
            (int)$pdo
                ->lastInsertId();

        audit(
            $pdo,
            (int)$u['user_id'],
            'resource.upload',
            'resource',
            $rid
        );

        json_response([
            'message' =>
                'Resource uploaded',

            'resource_id' =>
                $rid
        ], 201);
    }

    $name =
        bin2hex(
            random_bytes(16)
        ) .
        '.' .
        $ext;

    $destination =
        rtrim(
            $config[
                'upload_dir'
            ],
            '/\\'
        ) .
        DIRECTORY_SEPARATOR .
        $name;

    if (
        !move_uploaded_file(
            $f['tmp_name'],
            $destination
        )
    ) {
        json_response([
            'error' =>
                'Server could not save the uploaded file'
        ], 500);
    }

    try {

        $s = $pdo->prepare(
            "INSERT INTO resources
                (
                    uploaded_by,
                    course_id,
                    title,
                    resource_type,
                    description,
                    file_url,
                    original_file_name,
                    mime_type,
                    file_size,
                    status
                )
             VALUES(
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                'active'
             )"
        );

        $s->execute([
            $u['user_id'],
            $courseId,
            $title,
            'notes',
            $description,
            $name,
            $f['name'],
            $mime,
            (int)$f['size']
        ]);

        $rid =
            (int)$pdo
                ->lastInsertId();

        audit(
            $pdo,
            (int)$u['user_id'],
            'resource.upload',
            'resource',
            $rid
        );

        json_response([
            'message' =>
                'Resource uploaded',

            'resource_id' =>
                $rid
        ], 201);

    } catch (Throwable $e) {

        @unlink(
            $destination
        );

        throw $e;
    }
}

// ---------------------------------------------------------
// Resource download
// ---------------------------------------------------------

if (
    preg_match(
        '#^/api/resources/(\d+)/download$#',
        $path,
        $m
    ) &&
    $method === 'GET'
) {

    require_user($pdo);

    $rid =
        (int)$m[1];

    $s = $pdo->prepare(
        "SELECT
            file_url,
            original_file_name,
            mime_type,
            file_size,
            file_data
         FROM resources
         WHERE resource_id=?
         AND status='active'"
    );

    $s->execute([
        $rid
    ]);

    $r =
        $s->fetch();

    if (!$r) {
        json_response([
            'error' =>
                'Resource not found'
        ], 404);
    }

    $pdo->prepare(
        'UPDATE resources
         SET download_count=
            download_count+1
         WHERE resource_id=?'
    )->execute([
        $rid
    ]);

    $filename =
        preg_replace(
            '/[^A-Za-z0-9._ -]/u',
            '_',
            basename(
                (string)(
                    $r[
                        'original_file_name'
                    ] ?:
                    'download'
                )
            )
        );

    header(
        'Content-Type: ' .
        (
            $r['mime_type'] ?:
            'application/octet-stream'
        )
    );

    header(
        'Content-Disposition: attachment; filename="' .
        str_replace(
            '"',
            '',
            $filename
        ) .
        '"'
    );

    if (
        $r['file_data'] !==
        null
    ) {

        header(
            'Content-Length: ' .
            strlen(
                (string)$r[
                    'file_data'
                ]
            )
        );

        echo $r['file_data'];
        exit;
    }

    $base =
        realpath(
            $config[
                'upload_dir'
            ]
        );

    $file =
        $base
            ? realpath(
                $base .
                DIRECTORY_SEPARATOR .
                basename(
                    (string)$r[
                        'file_url'
                    ]
                )
            )
            : false;

    if (
        !$file ||
        !$base ||
        !str_starts_with(
            $file,
            $base .
            DIRECTORY_SEPARATOR
        ) ||
        !is_file($file)
    ) {
        json_response([
            'error' =>
                'File unavailable'
        ], 404);
    }

    header(
        'Content-Length: ' .
        filesize($file)
    );

    readfile($file);
    exit;
}

// ---------------------------------------------------------
// Notifications
// ---------------------------------------------------------

if (
    $path ===
    '/api/notifications' &&
    $method === 'GET'
) {

    $u =
        require_user($pdo);

    $s =
        $pdo->prepare(
            'SELECT *
             FROM notifications
             WHERE user_id=?
             ORDER BY created_at DESC
             LIMIT 100'
        );

    $s->execute([
        $u['user_id']
    ]);

    json_response([
        'items' =>
            $s->fetchAll()
    ]);
}

if (
    preg_match(
        '#^/api/notifications/(\d+)/read$#',
        $path,
        $m
    ) &&
    $method === 'PATCH'
) {

    $u =
        require_user($pdo);

    $s =
        $pdo->prepare(
            'UPDATE notifications
             SET read_at=NOW()
             WHERE notification_id=?
             AND user_id=?'
        );

    $s->execute([
        (int)$m[1],
        $u['user_id']
    ]);

    json_response([
        'updated' =>
            $s->rowCount()
    ]);
}

json_response([
    'error' =>
        'Route not found'
], 404);
