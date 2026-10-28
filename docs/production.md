# Running in production

The application runs as one Rails process with PostgreSQL and private S3-compatible storage. The Docker image pins Ruby 3.4.12, Bundler 2.6.9 and ImageMagick 7.1.2-34 Q8. The image installs PostgreSQL 18 client tools; application gems remain pinned in Gemfile.lock.

Build the image without runtime credentials:

```sh
docker build --tag lefty-wefty .
```

Asset compilation uses a dummy secret only during the build. It does not connect to a database, run migrations or create accounts. The final image runs as a nonroot user. Local database/upload configuration, credentials, logs and uploaded files are excluded from the image.

Use [`config/production.env.example`](../config/production.env.example) as a settings reference. Enter actual secrets through the hosting provider's secure environment settings. Do not commit a completed settings file or paste credentials into command lines, issues or logs.

## Database and startup

Create a fresh PostgreSQL database with no sample data. Use a migration role that owns the database/schema and a separate runtime role with schema usage, table SELECT/INSERT/UPDATE/DELETE and sequence USAGE/SELECT. Give the runtime role no schema CREATE privilege. Configure equivalent default privileges for tables and sequences subsequently created by the migration role.

Set DATABASE_URL to the runtime connection and MIGRATION_DATABASE_URL to the direct migration connection for that same database. Both require sslmode=verify-full; the application enforces certificate/hostname verification, SCRAM channel binding and a connection timeout. The default CA source is the system trust store. An explicit trusted CA bundle can be supplied using LEFTY_WEFTY_DB_SSLROOTCERT. Certificate verification cannot be disabled through these settings.

For a small instance, direct connections keep configuration simple: two request threads and a database pool of two. A pooled runtime endpoint may be used with the matching direct migration endpoint; prepared statements are disabled. Migrations always need a direct connection because they use session advisory locks.

The container entrypoint takes a PostgreSQL advisory lock, waits at most 30 seconds, and runs only db:migrate. Lock waits and individual migration statements are bounded; the migration process has a 180-second limit. A migration failure prevents Puma from starting. Existing transactions and PostgreSQL constraints remain responsible for data integrity. Review destructive or long-running future migrations before deploying them; startup automation does not make them safe automatically.

After migration, the entrypoint removes the migration URL from the web process environment and replaces itself with Puma. There is one process with up to two request threads. The production listener uses 0.0.0.0 and the supplied PORT. Development retains its localhost-only listener. GET /up reports application boot health without account or business data.

Public signup is disabled in production, including direct requests; existing owners can still log in. Establish the first owner through a trusted administrative Rails process after confirming the production database and HTTPS/storage checks. Supply a unique private password through protected input, and create the user and business in one transaction. Do not temporarily open public signup, publish shared credentials, run db:seed/db:reset or import a development database. Public demo access remains unavailable until a read-only workspace is implemented and verified.

## Private logos and background work

Production requires the s3 service. Disk storage is reserved for development and tests. Configure the S3 endpoint, region, private bucket and credentials using the environment variables in the example. Keep the bucket private; the app does not send public ACLs, return public object URLs or expose default Active Storage routes. Original and sanitized files both belong in persistent storage. Owner-authenticated Rails responses serve sanitized logos.

The S3 client verifies HTTPS certificates, uses path-style requests and bounded network timeouts/retries. A provider-specific CA bundle is supported through LEFTY_WEFTY_S3_CA_BUNDLE for isolated compatibility testing or a privately operated trusted service. It does not disable certificate verification.

Jobs execute inline in production; no Redis or background-worker service is required. Recovery sends are synchronous and attachment purges execute in the request process. Object-storage outages reject a new profile save while retaining the saved name/logo. Cleanup errors are logged without object keys or credentials. Interrupted or ambiguously acknowledged uploads can leave private unreferenced objects: periodically compare a protected bucket inventory with Active Storage metadata before removing any confirmed orphan. Do not delete objects based only on age.

## Recovery email

Keep LEFTY_WEFTY_BREVO_ENABLED=false and leave BREVO_API_KEY and LEFTY_WEFTY_MAIL_FROM unset. Password reset is currently unavailable. The server rejects reset requests and previously issued reset links without changing passwords or sessions. Production mail delivery and previews are disabled. Signed-in password changes still require the current password and rotate sessions. Development retains local capture and its fictional preview.

The optional delivery adapter remains in the source for future configuration; it is not part of this deployment.

## Domain and indexing

The intended origin is https://lefty-wefty.devs.surf. Production allows that host and, if explicitly configured, the actual assigned Render preview hostname. Health checks can reach /up without widening access to application routes. HTTPS/proxy settings and secure session cookies remain enabled.

Public indexing remains off until deliberately enabled after live checks. Preview-host requests remain noindex even when canonical-host indexing is enabled. Public canonical and share URLs come from the configured origin, never the request Host. Private/auth/token/error routes remain noindex and protected by authentication where required.

Configure DNS only after the actual service hostname and verification values exist. Preserve unrelated records. A CNAME cannot share its owner name with TXT or other records. Do not add unowned aliases.

## Backup and restore

Back up PostgreSQL, original/sanitized objects, their metadata and production configuration/keys together. Use a protected destination outside Git and an independently controlled backup destination. A source clone or a same-disk copy cannot recover lost hosted data.

Pause application writes and let active requests finish before capturing a consistent database/object set. Render Free has no general-purpose one-off shell; use a trusted machine with the pinned tools and securely configured direct database/storage access. Do not put production backup credentials on a public CI runner.

Run pg_dump with custom format, no-owner and no-acl, supplying credentials through secure environment or a protected PostgreSQL service file rather than a URL argument. Then export all blob objects using the same protected production environment:

```sh
LEFTY_WEFTY_BACKUP_CONFIRMED_MAINTENANCE=true bundle exec ruby bin/rails runner script/export_logos.rb /secure/new-export
```

The exporter refuses existing directories/Git worktrees, verifies sizes/MD5 checksums, and writes a SHA-256 manifest with protected files. Encrypt and copy the database dump, object export and required settings/keys to the chosen independent destination. Verify that copy before considering it a backup.

Restore first into a new isolated database named lefty_wefty_restore_*, using pg_restore with exit-on-error, no-owner and no-acl. Reapply appropriate runtime grants. Create a different private bucket and configure the restored application to use it. With its database metadata restored, run:

```sh
LEFTY_WEFTY_RESTORE_CONFIRM=isolated-target \
LEFTY_WEFTY_RESTORE_EXPECTED_BUCKET=YOUR_SEPARATE_PRIVATE_BUCKET \
bundle exec ruby bin/rails runner script/restore_logos.rb /secure/verified-export
```

The restore checks every file and metadata record before uploading, refuses the source bucket, and verifies downloaded bytes. Repeated runs accept only already-restored objects with matching content. Verify login, tenant boundaries, stock/sales/history and owner-only logo access before any separately approved cutover. A restore into a disposable CI database/object store proves the procedure's compatibility; it does not prove recovery from a live provider or an off-machine backup.
