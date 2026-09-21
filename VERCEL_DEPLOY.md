# UniLink — Vercel deployment

This build uses Vercel's container runtime to run the existing PHP application. Do not use file-backed mode on Vercel: the function/container filesystem is not durable.

## 1) Create a MySQL-compatible database

Use your existing managed MySQL database (for example Aiven) or a MySQL-compatible provider. Import:

`database/unilink_vercel.sql`

This schema intentionally does not run `CREATE DATABASE` or `USE`, so it can be imported into the database your provider already created.

## 2) Set Vercel environment variables

Required:

- `DATA_DRIVER=mysql`
- Either `DATABASE_URL=mysql://USER:PASSWORD@HOST:PORT/DATABASE`
- Or all of: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `RESOURCE_STORAGE=database`
- `MAX_UPLOAD_BYTES=4000000`

For a provider that requires a CA certificate, also set `DB_SSL_CA` to the PEM certificate content. Newlines can be literal newlines or `\n` sequences.

Do not upload a real `.env` file to GitHub.

## 3) Deploy

Keep these files at the Vercel project root:

- `Dockerfile.vercel`
- `Caddyfile`
- `vercel.json`

Deploy from GitHub or the Vercel CLI. With the CLI:

```bash
npm i -g vercel@latest
vercel login
vercel deploy --prod
```

## 4) Verify

Open:

`https://YOUR-PROJECT.vercel.app/api/health`

Expected result includes:

```json
{"ok":true,"database":"connected"}
```

Then test with two browser sessions:

1. Register User A and User B.
2. Login A in a normal window and B in an incognito/private window.
3. A creates a post and sends B a connection request.
4. B accepts and messages A.
5. A replies.
6. Upload a PDF/DOCX/PPTX smaller than 4 MB.
7. Refresh and confirm everything persists.
8. Logout and log back in; confirm the data still exists.

## Why this build differs from the XAMPP build

On Vercel, PHP runs in autoscaling containers. Local JSON files, normal PHP file sessions, and local uploaded files are not durable across instances. This build therefore uses MySQL for application data, MySQL-backed PHP sessions, and MySQL BLOB storage for small classroom resource uploads.
