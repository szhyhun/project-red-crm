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
QUEUE=media bundle exec rake resque:work
```

The worker is required once media processing, imports, and notifications enqueue
jobs. It may remain idle with the current manually registered-media slice.

## Start the portal

From `project-red-crm-ui`:

```bash
cp .env.example .env.local
pnpm install
pnpm dev -- --port 3001
```

The portal runs at `http://localhost:3001` and calls the API at
`http://localhost:3002/api/v1` by default.

## Tests

Focused RSpec coverage lives under `spec/` and covers the important current
business and permission boundaries. Tests are not run automatically during
iteration. Run them only when intentionally validating a change:

```bash
rbenv exec ruby bin/rspec
```
