# Local development

## Required services

ProjectRed CRM uses PostgreSQL and Redis locally.

```bash
brew services start postgresql@14
redis-server --daemonize yes
```

## Start the API

From `project-red-crm`:

```bash
rbenv exec bundle install
rbenv exec ruby bin/rails db:prepare
rbenv exec ruby bin/rails db:seed
rbenv exec ruby bin/rails server
```

The seed is idempotent: it creates the ProjectRed demo workspace only when its
records are missing and does not overwrite later edits. Override the default
local password with `DEMO_PASSWORD=...`. Production skips demo data unless
`SEED_DEMO_DATA=true` is explicitly set.

Use Ruby from the project's rbenv installation. The macOS system Ruby is not
the application runtime.

The health endpoint is `http://localhost:3010/up`.

## Start the worker

In a second terminal:

```bash
cd /Users/serhiizhyhun/Desktop/projects/project-red-crm
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES QUEUE='*' bundle exec rake resque:work
```

The worker verifies local media uploads and sends lifecycle email jobs. Local
development uses Rails' `:test` delivery method, so it never sends external mail.
Inspect a branded message through Rails mailer previews at
`http://localhost:3010/rails/mailers/customer_mailer`.

The development Action Cable adapter also uses Redis. This is intentional: chat
notifications are enqueued by the Resque worker, which is a separate process
from Rails. The worker and the web process must share Redis or new messages will
be saved but other open tabs will not receive live updates and unread badges.
When testing through Nginx or another reverse proxy, the `/cable` route must use
HTTP/1.1 and forward both `Upgrade` and `Connection` headers. Without those
headers the browser repeatedly falls back to an ordinary HTTP request, so the
worker can successfully broadcast while no browser receives it.

## Start the scheduler

In a third terminal, run the recurring jobs registered in
`config/resque_schedule.yml`:

```bash
cd /Users/serhiizhyhun/Desktop/projects/project-red-crm
RAILS_ENV=development bundle exec rake environment resque:scheduler
```

The scheduler is a long-running process, like the worker. It is not started by
the Rails server. Use `Ctrl-C` to stop it.

## Production email settings

Production uses SMTP. Set these environment variables in the production runtime,
not in the repository:

```bash
MAILER_FROM='ProjectRed <hello@your-verified-domain>'
AUTH_MAILER_FROM='ProjectRed <hello@your-verified-domain>'
MAILER_HOST='portal.your-domain'
PORTAL_URL='https://portal.your-domain'
SMTP_ADDRESS='smtp.provider.com'
SMTP_PORT='587'
SMTP_USERNAME='smtp-user'
SMTP_PASSWORD='smtp-password'
SMTP_AUTHENTICATION='plain'
SMTP_ENABLE_STARTTLS_AUTO='true'
```

Use a verified sender domain with your email provider. SMTP credentials are secrets.

`OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` is required only for local macOS
workers because Resque forks child processes. Linux production workers do not
need this setting.

## Start the portal

From `project-red-crm-ui`:

```bash
cp .env.example .env.local
pnpm install
npm run dev
```

The combined UI runs at `http://localhost:3011` and calls the API at
`http://localhost:3010/api/v1` by default. When using a surface subdomain, the
browser automatically sends API requests to the matching local host and port
(`portal.localhost:3010` or `crm.localhost:3010`). This is important because
the Rails session cookie is `SameSite=Lax`; matching the host keeps portal and
CRM XHR requests first-party in local development. For surface-boundary
testing, use
`http://crm.localhost:3011` for staff and `http://portal.localhost:3011` for
customers. Configure `CRM_UI_ORIGINS` with all three local origins. Both ports
are configured in the two repositories, so no port flags are needed when
starting either app.

Task description/comment attachments use local `storage/board_media` by
default. To exercise the production storage path, set
`PROJECT_RED_BOARD_MEDIA_BUCKET`, `PROJECT_RED_BOARD_MEDIA_CDN_URL`, and
`AWS_REGION` in the API environment. The production bucket should remain
private; the API returns authorized temporary preview/download URLs.

Chat attachments use a separate private boundary. Local development stores
them under `storage/chat_media` by default. To exercise the production path,
set `PROJECT_RED_CHAT_MEDIA_BUCKET` and `AWS_REGION`; do not add a public CDN
URL for chat files. The API serializes authorized relative `preview_path` and
`download_path` values, and the UI must resolve them with its shared asset URL
helpers. The API origin performs the membership check before streaming a
preview, while downloads may use a short-lived signed S3 URL after that check.

Chat history cleanup defaults to two months per conversation. Set a
conversation's `retention_period` to `two_months`, `six_months`, `one_year`, or
`forever` through the conversation API when a different policy is needed, then
run the cleanup manually with `bundle exec rake conversations:purge_expired`.
Production runs the recurring entry in `config/resque_schedule.yml` through
Resque Scheduler; local development requires starting the scheduler process
manually.

## Stripe test payments

Set the Rails variables `STRIPE_SECRET_KEY=sk_test_...` and
`STRIPE_WEBHOOK_SECRET=whsec_...`. Set
`NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...` in the portal. Forward signed
events to the API with:

```bash
stripe listen --forward-to localhost:3010/api/v1/webhooks/stripe
```

Use Stripe test card `4242 4242 4242 4242`, any future expiry, and any CVC in
the portal's Payment Element. The Rails API never receives the card number.

## Tests

Focused RSpec coverage lives under `spec/` and covers the important current
business and permission boundaries. Tests are not run automatically during
iteration. Run them only when intentionally validating a change:

```bash
env -u DATABASE_URL TEST_DATABASE_URL=postgresql://localhost/project_red_crm_test \
  RAILS_ENV=test bundle exec rspec
```

The `DATABASE_URL` override is intentional: local shells commonly point it at
the development database, while Rails uses the test database only when the
test URL is explicit. In Codex or another sandboxed environment, grant local
PostgreSQL/elevated access before the first run; do not make an unprivileged
attempt first.
