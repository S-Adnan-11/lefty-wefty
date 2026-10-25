# Lefty-Wefty

An owner-operated inventory application built with Ruby on Rails, PostgreSQL, and server-rendered ERB.

Create a business workspace, manage products, receive stock, and make corrections with an auditable movement history. Each account owns one isolated business. Quantities are whole units; prices are integer minor units. Workspaces currently use NGN and Africa/Lagos.

## Requirements

- Ruby **3.4.12**, Bundler **2.6.9**, and a native extension compiler (RubyInstaller with Devkit on Windows).
- PostgreSQL **18.6**, including `psql` and `pg_dump` on PATH.
- Rails **8.1.4** and all other gems are pinned in `Gemfile.lock`.

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

### Fictional sample data and local recovery

`ruby bin/rails db:seed` adds two fictional businesses with different stock and a shared SKU. Repeating it preserves existing products, balances, account passwords, and history. Sample accounts have random passwords with no shared credential.

In development, open [mail previews](http://localhost:3000/rails/mailers/passwords_mailer/reset?email=cedar@example.test) to choose a sample account password. Add `?email=your-address` to preview another existing account. Previews are a local developer feature. Reset requests retain mail in memory; **external email delivery is not configured or verified**. A successful password reset revokes existing sessions. Reset links expire after 15 minutes.

## Using stock

1. Create a product with a name, SKU, price in minor units, and low-stock threshold. For NGN, 125000 kobo displays as NGN 1,250.00.
2. Start at zero, or supply an opening quantity to record an opening movement.
3. Open the product and choose **Receive stock** with a positive whole quantity.
4. Choose **Adjustment** with a nonzero signed quantity and a reason to correct a count. Negative balances are rejected.
5. Check the movement history and workspace indicators. An active product is low stock at or below its threshold, including zero.
6. Archive a product to remove it from active lists. Its balance and history remain available; new stock changes are disabled.

SKUs are trimmed and uppercased, accept letters, numbers, dots, underscores and hyphens, and are unique per business. Stock and thresholds are limited to 2,147,483,647 units; prices to 999,999,999,999 minor units. Product search, status filtering, and movement history use pages of 20 records.

## Data integrity

The authenticated owner's business scopes records, writes, search, and workspace totals. Submitted ownership fields are ignored. Composite foreign keys prevent movements from connecting products and actors from different businesses.

`Stock::Apply` locks a product row in a PostgreSQL transaction, checks the balance, appends a movement, and updates quantity atomically. Receipt and adjustment forms carry a UUID enforced by a unique database index. Retrying the same submitted form returns its existing movement; reusing its identity with different data is rejected. Opening stock is part of product creation's transaction.

Balances are readonly on ordinary product saves. Movement records have no edit/delete routes and are protected against update/delete in both Active Record and PostgreSQL. Database administrators can still change data; these guarantees cover application operations. Migrations and `db/structure.sql` preserve composite constraints and the append-only trigger.

Authentication uses Rails' generator and bcrypt, with signed HttpOnly session cookies, CSRF protection, 14-day session expiry, and rate limits for signup, login and recovery. Rate limits use bounded memory in one local server process; they reset on restart and are not coordinated across multiple processes.

## Checks

```sh
ruby bin/rails test
ruby bin/rails zeitwerk:check
ruby bin/rubocop
ruby bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
ruby bin/bundler-audit check --update
```

Tests require real PostgreSQL and exclusively use `lefty_wefty_test`. The concurrency tests commit records on independent connections and truncate that dedicated test database afterward. Do not keep useful data there. Tests cover tenant boundaries, rollback, stock reconciliation, retries, concurrent updates, and database constraints.

If PostgreSQL cannot connect, check the server process, host, port, local configuration, and project role permissions. If `pg_dump` is missing, add the PostgreSQL bin directory to PATH before migrating or dumping the SQL schema. On Windows, complete RubyInstaller's `ridk install 1` step if the Devkit reports an uninitialized signing keyring.

The application currently provides accounts, products, and inventory movements. It does not record sales, collect payments, send external email, or provide production hosting.
