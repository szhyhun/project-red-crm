# ProjectRed CRM API

Rails API for ProjectRed's ordering, listing production, delivery, billing, and customer-portal workflows.

## Local services

The API uses PostgreSQL and Redis/Resque locally.

```sh
brew services start postgresql@14
brew services start redis
bin/setup
bin/rails server
QUEUE='*' bundle exec rake resque:work
# In another terminal, run recurring jobs from config/resque_schedule.yml.
RAILS_ENV=development bundle exec rake environment resque:scheduler
```

Local CRM ports are fixed to avoid collisions with the other workspace apps:
the Rails API listens on `http://localhost:3010` and the CRM UI listens on
`http://localhost:3011`. The local `PORT=3010` setting and Puma default make
the plain `bin/rails server` command use the API port.

If the Homebrew Redis service cannot start through `launchctl`, use the local
development daemon instead:

```sh
redis-server --daemonize yes
```

`bin/setup` creates and migrates the local database. It does not run the test suite.

## Production deployment

Production runs on the existing Project Red EC2 instance in `us-west-2`. The
CRM has its own application services and database, but intentionally shares
the existing infrastructure:

- PostgreSQL database `project_red_crm` on the existing `picaivid-db` RDS
  instance. Do not create a second RDS instance for normal CRM growth.
- Local Redis on the EC2 instance for Resque, capped at 128 MB.
- Private S3 media bucket `project-red-crm-prod-media-250830192304`, served
  through its CloudFront distribution. Deployment artifacts are stored
  separately and expire after 30 days.
- Board attachments use a separate private S3 bucket configured with
  `PROJECT_RED_BOARD_MEDIA_BUCKET` and `PROJECT_RED_BOARD_MEDIA_CDN_URL`.
  The API authorizes every preview/download request before issuing a temporary
  URL; local development stores them under `storage/board_media`.
- Chat attachments use their own private S3 bucket configured with
  `PROJECT_RED_CHAT_MEDIA_BUCKET`. The API authorizes every preview/download
  request and streams previews through the API origin; local development
  stores them under `storage/chat_media`.
- Chat messages and their private attachments are retained for two months by
  default. Each conversation can be configured to retain history for two
  months, six months, one year, or forever. Production runs the recurring job
  in `config/resque_schedule.yml` through `project-red-crm-scheduler`.
- Rails API on port `3003`, behind Nginx as `api.projectred.ca`.
- Resque worker: `project-red-crm-worker`.
- Resque Scheduler: `project-red-crm-scheduler`.

### Normal release

Push or merge to `main`. The API deployment workflow at
[.github/workflows/deploy-production.yml](.github/workflows/deploy-production.yml)
runs RuboCop and the test suite before it can deploy. It uses GitHub OIDC to
upload a release artifact to S3 and invokes the host through AWS Systems
Manager; no long-lived AWS access key or production secret is stored in GitHub.

For a controlled redeploy, use **Actions → Deploy production → Run workflow**
and choose `main`.

The repository variables required by the workflow are `AWS_REGION`,
`AWS_ROLE_ARN`, `DEPLOY_BUCKET`, and `INSTANCE_ID`. Keep credentials out of
repository variables and source code.

The host release script:

1. installs the production bundle and runs `rails db:migrate`;
2. activates the new release under `/srv/project-red-crm-api`;
3. restarts `project-red-crm-api`, `project-red-crm-worker`, and
   `project-red-crm-scheduler`;
4. waits up to 60 seconds for `http://127.0.0.1:3003/up` before declaring the
   release healthy.

If the service cannot start or become healthy, the script restores the prior
application release. Database migrations are not automatically reversed, so
review migrations carefully before merging.

### Production configuration and checks

Runtime secrets live only on the host in `/etc/project-red-crm/api.env`
(permissions `0600`). It holds `RAILS_MASTER_KEY`, `DATABASE_URL`, Redis/S3
settings, permitted origins, and future SMTP/Stripe credentials. Do not commit
this file or `config/master.key`.

The API uses two separate CORS boundaries. `CRM_UI_ORIGINS` (or
`CRM_UI_ORIGIN`) is the credentialed CRM UI and Action Cable allowlist. The
optional `PUBLIC_SITE_ORIGINS`/`PUBLIC_SITE_ORIGIN` allowlist can call only the
unauthenticated `/api/v1/public/*` resources and never receives session
credentials. Keep the temporary CRM `sslip.io` origin and the final CRM DNS
origin together while migrating; see [the security contract](docs/security.md)
for the storage, upload, and webhook rules that go with this boundary.

After changing the host environment file, validate its shell syntax and
restart the API and worker through AWS Systems Manager:

```sh
sudo /bin/bash -n /etc/project-red-crm/api.env
sudo systemctl restart project-red-crm-api project-red-crm-worker project-red-crm-scheduler
sudo systemctl status project-red-crm-api project-red-crm-worker project-red-crm-scheduler --no-pager
sudo journalctl -u project-red-crm-api -u project-red-crm-worker -u project-red-crm-scheduler -n 100 --no-pager
```

Health checks from the host are:

```sh
curl --fail -H 'Host: api.projectred.ca' http://127.0.0.1/up
systemctl is-active project-red-crm-api project-red-crm-worker redis-server nginx
```

Before first public use, create DNS `A` records for `api.projectred.ca` and
`crm.projectred.ca` pointing to the EC2 public IP, then issue/renew certificates
with Certbot for both names. Production email delivery remains disabled until
valid SMTP settings are added to `api.env`; add Stripe production secrets there
as well when billing is enabled.

Production releases run migrations but never run `db:seed`. The demo seed is
deliberately disabled in production unless `SEED_DEMO_DATA=true` is supplied;
do not use its source-controlled default password for a real account. Create
production admin and customer accounts with unique credentials instead.

### Temporary preview domain

Until Project Red DNS is available, all three Project Red services are exposed
through these temporary, HTTPS-enabled `sslip.io` names:

- `https://crm.44.248.89.217.sslip.io`
- `https://api.44.248.89.217.sslip.io`
- `https://marketing.44.248.89.217.sslip.io`

`sslip.io` automatically resolves the embedded IP address. It is a short-term
preview route only, not a production domain. When the real DNS records and
certificates are ready, remove the temporary Nginx virtual-host file, issue
certificates for the real names, and set `/etc/project-red-crm/api.env` back to
the final values:

```sh
API_ALLOWED_HOSTS=api.projectred.ca
CRM_UI_ORIGIN=https://crm.projectred.ca
CRM_UI_ORIGINS=https://crm.projectred.ca
PORTAL_URL=https://crm.projectred.ca
MAILER_HOST=api.projectred.ca
```

Then set `NEXT_PUBLIC_CRM_API_URL=https://api.projectred.ca/api/v1` in
`/etc/project-red-crm/ui.env` and redeploy both applications from `main`.

### Related instance services

Picaivid's application services are currently stopped without deleting their
code or data. To bring them back later:

```sh
sudo systemctl enable --now picaivid-rails picaivid-react
```

Do not stop the local PostgreSQL service: it serves the Project Red marketing
site. Do not stop or delete the shared RDS instance: it serves the CRM database
as well as its existing workload.

## Related applications

- Public ordering site: `projectred.ca`
- CRM UI: `../project-red-crm-ui`
- API: `api.projectred.local` in development and `api.projectred.ca` in production

See `docs/architecture.md` for the product boundary and storage model.

## Documentation

- [Product guide](docs/product-guide.md): customer-facing features and configuration in plain language.
- [Engineering documentation](docs/README.md): architecture, access rules, operations, integrations, and local development.
