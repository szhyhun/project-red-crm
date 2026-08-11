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
rbenv exec ruby bin/rails server -p 3002
```

Use Ruby from the project's rbenv installation. The macOS system Ruby is not
the application runtime.

The health endpoint is `http://localhost:3002/up`.

## Start the worker

In a second terminal:

```bash
cd /Users/serhiizhyhun/Desktop/projects/project-red-crm
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES QUEUE='*' bundle exec rake resque:work
```

The worker verifies local media uploads and sends lifecycle email jobs. Local
development uses Rails' `:test` delivery method, so it never sends external mail.
Inspect a branded message through Rails mailer previews at
`http://localhost:3002/rails/mailers/customer_mailer`.

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
pnpm dev -- --port 3001
```

The portal runs at `http://localhost:3001` and calls the API at
`http://localhost:3002/api/v1` by default.

## Stripe test payments

Set the Rails variables `STRIPE_SECRET_KEY=sk_test_...` and
`STRIPE_WEBHOOK_SECRET=whsec_...`. Set
`NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...` in the portal. Forward signed
events to the API with:

```bash
stripe listen --forward-to localhost:3002/api/v1/webhooks/stripe
```

Use Stripe test card `4242 4242 4242 4242`, any future expiry, and any CVC in
the portal's Payment Element. The Rails API never receives the card number.

## Tests

Focused RSpec coverage lives under `spec/` and covers the important current
business and permission boundaries. Tests are not run automatically during
iteration. Run them only when intentionally validating a change:

```bash
rbenv exec ruby bin/rspec
```
