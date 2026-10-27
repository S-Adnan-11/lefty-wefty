# Lefty-Wefty

Lefty-Wefty helps small businesses track products, stock and sales. It uses Ruby on Rails, PostgreSQL and server-rendered ERB.

Manage products, receive stock, record sales, and cancel completed sales with an auditable stock history. Each account owns one isolated business. Enter prices in naira; storage and calculations use integer minor units. Quantities are whole units. Businesses use NGN and Africa/Lagos.

## Requirements

- Ruby **3.4.12**, Bundler **2.6.9**, and a native extension compiler (RubyInstaller with Devkit on Windows).
- PostgreSQL **18.6**, including `psql` and `pg_dump` on PATH.
- Rails **8.1.4** and all other gems are pinned in `Gemfile.lock`.
- ImageMagick **7**, with PNG, JPEG and WebP support, for logo validation and processing. The local Windows configuration uses **7.1.2-34**.

## Local setup

Install the requirements, clone the repository, and run:

```sh
bundle install
```

Provision dedicated databases using an administrative PostgreSQL connection:

```sql
CREATE ROLE lefty_wefty LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
\password lefty_wefty
CREATE DATABASE lefty_wefty_development OWNER lefty_wefty;
CREATE DATABASE lefty_wefty_test OWNER lefty_wefty;
```

The `\password` command prompts for a local database password. Check for existing databases before creating them; keep other projects' databases separate.

Copy `config/database.local.yml.example` to `config/database.local.yml` and enter your local connection details. The latter file is ignored by Git. Alternatively, set `LEFTY_WEFTY_DB_HOST`, `LEFTY_WEFTY_DB_PORT`, `LEFTY_WEFTY_DB_USER`, and `LEFTY_WEFTY_DB_PASSWORD` in your shell. The default port is 5432.

```sh
ruby bin/rails db:migrate
ruby bin/rails db:migrate RAILS_ENV=test
ruby bin/rails server
```

Open [localhost:3000](http://localhost:3000). The server binds to `127.0.0.1`. On Windows PowerShell, the environment-specific migration can also be run as:

```powershell
$env:RAILS_ENV = "test"
ruby bin/rails db:migrate
Remove-Item Env:RAILS_ENV
```

Use **Create account** to create an owner and business together. Passwords require at least 12 characters and cannot exceed bcrypt's 72-byte limit. No external service is required.

### Logo storage

Copy `config/uploads.local.yml.example` to the ignored `config/uploads.local.yml`. Set `root` to an absolute directory outside the checkout on durable storage, and `image_magick_path` to the directory containing `magick` if it is absent from PATH. Alternatively, use `LEFTY_WEFTY_UPLOAD_ROOT` and `LEFTY_WEFTY_IMAGE_MAGICK_PATH`. Without configuration, development uses the ignored `storage` directory; tests always use `tmp/test-uploads`.

Back up the upload directory, database (including Active Storage metadata), local configuration, and Rails credentials/key together. Original logo files and sanitized display images are both needed. Restoring the database alone does not restore files. Keep ImageMagick and the repository's `config/image_policy/policy.xml` available after restoration.

Production requires an explicitly configured persistent upload root or a named service using `LEFTY_WEFTY_STORAGE_SERVICE` and a corresponding Rails storage configuration. A provider and its persistence must be verified before accepting live uploads; no hosted storage provider is included. An ephemeral web-service filesystem is unsuitable for durable logos.

### Fictional sample data and local recovery

`ruby bin/rails db:seed` adds two fictional businesses with different stock and a shared SKU. Repeating it preserves existing products, balances, account passwords, and history. Sample accounts have random passwords with no shared credential.

In development, **Forgot your password?** prepares a reset message in Action Mailer's in-memory deliveries. It does not send email to an inbox. Known and unknown email addresses receive the same acknowledgement. A valid reset link lasts 15 minutes; opening it does not change a password. Saving a valid new password revokes the account's existing sessions and invalidates previous reset links.

The [development mail preview](http://localhost:3000/rails/mailers/passwords_mailer/reset) shows the HTML/plain-text templates with a fictional address and an unusable link. It does not look up accounts or retrieve a requested message, and an `email` query parameter does not select a user. For local request/capture testing, use one Rails console process with a disposable account and `app.post "/passwords", params: { email_address: "your-disposable-address@example.test" }`; inspect the corresponding `ActionMailer::Base.deliveries.last` in that process. Deliveries in a running web server are not shared with a separate console. Treat messages and reset links as credentials; keep them out of logs, screenshots and source control.

Production previews and recovery delivery are disabled. External email remains unconfigured and unverified. Before enabling `config.x.password_recovery_delivery = :email`, configure and verify the mail transport, an owned `LEFTY_WEFTY_MAIL_FROM` sender and `LEFTY_WEFTY_APP_HOST` host. Development uses the reserved `example.test` sender only for local capture. No SMTP account or hosted email service is included.

## Using stock

1. Create a product with a name, optional product code, selling price in naira, and low-stock reminder. Enter `1250`, `1250.5`, or `1,250.50`; `1,250.50` stores exactly 125050 minor units. Invalid grouping, signs, exponents, overprecision and amounts outside ₦0.01–₦9,999,999,999.99 are rejected without rounding.
2. Start at zero, or supply starting stock to record the first stock-history entry.
3. Open the product and choose **Receive stock** with a positive whole quantity.
4. Choose **Correct stock**, select **Add to stock** or **Remove from stock**, and enter a positive quantity and a reason. Negative balances are rejected.
5. Check the movement history and workspace indicators. An active product is low stock at or below its threshold, including zero.
6. Archive a product to remove it from active lists. Its balance and history remain available; new stock changes are disabled.

Product codes (also called SKUs) are trimmed and uppercased, accept letters, numbers, dots, underscores and hyphens, and are unique per business. A blank new-product code generates a stable `LW-` code with bounded collision retries; a blank edit keeps the current code. Stock and reminder quantities are limited to 2,147,483,647 units; prices to 999,999,999,999 minor units. Product search, status filtering, and stock history use pages of 20 records.

The account menu contains **My account**, **Business settings**, and **Log out**. My account shows the login email and changes passwords using the current password and matching confirmation. A successful change replaces the current session and revokes other sessions; email editing is unavailable. Business settings changes the business name and uploads, replaces or removes a logo. PNG, JPEG and WebP still images up to 2 MB, 4096 pixels per side and 8 million pixels total are supported. Content checks and restricted decoding validate images; display copies are stripped of metadata and fit within 512×512 pixels. Failed validation keeps the saved name and logo. Both uploading and viewing logos require the authenticated owner; default Active Storage public/signed-blob routes are disabled.

## Using sales

1. Open **Sales → New sale**, select active products, and enter positive whole quantities. Leave unused lines empty. Each product can appear once, with up to 100 lines per sale; **Add product line** adds more fields.
2. **Save draft for review** shows the server's product prices and total. Drafts do not reserve or deduct stock. You can edit or discard them.
3. **Record sale** rechecks active products, current prices, and stock. A changed price or edited draft requires renewed review. If any line lacks stock, the entire sale stays a draft and no stock changes. Edit it or receive stock, then retry.
4. A completed sale records its original product names, SKUs, prices, quantities, total, confirmation time, and owner. Later product edits and archiving preserve those snapshots. Follow **Product stock history**; sale movements link back to their sale.
5. To correct a recorded sale, enter a reason, tick the explicit confirmation, and choose **Cancel sale**. This cancels the entire sale and restores exactly its original quantities, even for archived products. Deductions, snapshots, and linked reversals remain visible. A cancelled sale cannot be reactivated.

The application records sales and stock; it does not collect or refund money. There are no partial voids, discounts, tax calculations, manual sale price overrides, or backdated sales. Line totals and sale totals use integer minor units and must fit a signed 64-bit integer (maximum 9,223,372,036,854,775,807). A reversal that would exceed the stock quantity limit is rejected atomically; correct the physical stock count before retrying.

Sales lists have status filters and 20-record pagination. Repeated creation, confirmation, and void submissions resolve to their existing result. Reusing a submission identity with different items or a completed void with another reason is rejected. A discarded draft's submission identity is retained, so a browser retry cannot recreate it; start a new sale instead.

## Dashboard and monthly sales

The overview shows active stock, products at or below their low-stock threshold, recent recorded sales and movements, and the current business month's completed sale count and value. Archived products are excluded from current stock indicators. Recent sales show completed and cancelled records with their status; drafts remain in the sales list.

Open **Reports** for monthly completed sales, units sold, and sales value. First and last months use `YYYY-MM` and are both included. The default is the current business-local month. Use This month, Last 3 months, Last 12 months, or the custom first/last month controls. Each request allows up to 36 months. Empty months appear as zero, and the current month is labelled month to date. The table includes exact range totals, business currency/timezone, and generation time.

Only currently confirmed, nonvoided sales contribute, grouped by confirmation time in the business timezone. Later voids remove the original month's contribution, so historical summaries can change. Archived or renamed/repriced products retain their recorded sale values. This is a current-state sales summary; it does not calculate profit, tax, payments, or money collected.

The parameterized raw SQL is in [`Reports::MonthlySales`](app/services/reports/monthly_sales.rb). It filters authorized orders by a half-open UTC timestamp interval, aggregates item quantities to one row per order, sums each order's value once, and joins monthly aggregates to a calendar-month series. Two equal-value orders both count. Rails stores confirmation timestamps as UTC values in PostgreSQL `timestamp without time zone`; explicit conversions keep grouping independent of the database session timezone. For Lagos, 23:30 UTC on a month's final day belongs to the next local month. Money remains integral through SQL aggregation, Ruby, and display.

Products support name/SKU search and active, archived, or low-stock filters. Sales support status and exact sale number filtering (for example, `123` or `#123`). **Stock history** filters stock history by product and movement type, including archived products and linked sale reversals. Lists use stable 20-row pagination with filters in GET URLs, clear-filter links, and ordinary server forms that work without JavaScript. Invalid page values return the first page; valid page numbers past the end show the final page.

## Data integrity

The authenticated owner's business scopes records, writes, search, and workspace totals. Submitted ownership fields are ignored. Composite foreign keys prevent movements from connecting products and actors from different businesses.

`Stock::Apply` locks a product row in a PostgreSQL transaction, checks the balance, appends a movement, and updates quantity atomically. Receipt and adjustment forms carry a UUID enforced by a unique database index. Retrying the same submitted form returns its existing movement; reusing its identity with different data is rejected. Opening stock is part of product creation's transaction.

Balances are readonly on ordinary product saves. Movement records have no edit/delete routes and are protected against update/delete in both Active Record and PostgreSQL. Database administrators can still change data; these guarantees cover application operations. Migrations and `db/structure.sql` preserve composite constraints and the append-only trigger.

`Sales::Draft` saves items and a server-derived quote with a review token and revision. Submitted amounts cannot determine recorded prices. `Sales::Confirm` locks the saved order, then products in ascending ID order, and calls `Stock::Apply` within one outer transaction. Item snapshots, all deductions, and confirmation commit together. `Sales::Void` uses the same lock order and transaction boundary for its state and reversals. Product updates, archiving, receipts, and adjustments also serialize on product rows. An exception in a line's stock write rolls back the complete operation.

Transactions prevent partial writes; submission identities and locked state transitions prevent duplicate effects from retries. Sale movements keep distinct deterministic identities per item and type, while receipt/adjustment uniqueness stays unchanged. Composite foreign keys enforce business ownership across orders, products, items, actors, movements, and reversal references. Database triggers protect recorded sales/items and check complete snapshots, totals, deductions, and reversals at transaction commit. Keep the SQL schema dump: a Ruby schema alone cannot preserve these PostgreSQL features.

| Table | Purpose |
| --- | --- |
| `orders` | Business-owned draft, confirmed, or voided sale; quote/revision, total, timestamps and attribution |
| `order_items` | Product/order join, whole quantity, and immutable confirmation snapshots |
| `sale_submissions` | Business-scoped creation identity retained after a draft is discarded |
| `inventory_logs` | Append-only stock ledger; sale item and original deduction references for reversals |

Authentication uses Rails' generator and bcrypt, with signed HttpOnly session cookies, CSRF protection, 14-day session expiry, and rate limits for signup, login and recovery. Rate limits use bounded memory in one local server process; they reset on restart and are not coordinated across multiple processes.

## Checks

```sh
ruby bin/rails test
ruby bin/rails zeitwerk:check
ruby bin/rubocop
ruby bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
ruby bin/bundler-audit check --update
```

Tests require real PostgreSQL and exclusively use `lefty_wefty_test`. The concurrency tests commit records on independent connections and truncate that dedicated test database afterward. Do not keep useful data there. Tests cover tenant boundaries, stale reviews, immutable sales, whole-sale voids, rollback, stock reconciliation, retries, concurrent stock/sale updates, and database constraints.

If PostgreSQL cannot connect, check the server process, host, port, local configuration, and project role permissions. If `pg_dump` is missing, add the PostgreSQL bin directory to PATH before migrating or dumping the SQL schema. On Windows, complete RubyInstaller's `ridk install 1` step if the Devkit reports an uninitialized signing keyring.

The application provides accounts, business profiles/logos, products, stock history, sales, cancellations and monthly reports. It does not collect payments, send external email, or provide production hosting.
