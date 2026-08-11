# ProjectRed CRM API

Rails API for ProjectRed's ordering, listing production, delivery, billing, and customer-portal workflows.

## Local services

The API uses PostgreSQL and Redis/Resque locally.

```sh
brew services start postgresql@14
brew services start redis
bin/setup
bin/rails server
QUEUE='media' bundle exec rake resque:work
```

If the Homebrew Redis service cannot start through `launchctl`, use the local
development daemon instead:

```sh
redis-server --daemonize yes
```

`bin/setup` creates and migrates the local database. It does not run the test suite.

## Related applications

- Public ordering site: `projectred.ca`
- CRM UI: `../project-red-crm-ui`
- API: `api.projectred.local` in development and `api.projectred.ca` in production

See `docs/architecture.md` for the product boundary and storage model.
