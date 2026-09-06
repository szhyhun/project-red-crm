# Working in this repository

## Run the suite once, at the end

Running specs is fine, but it is expensive, so run them deliberately rather
than reflexively:

- **Run the full suite when a feature is complete, before pushing.** That is
  the run that matters, and it is the one to report.
- **Do not run after every iteration** — not after each edit, each file, or
  each green step along the way.
- While actually diagnosing a failure, a single targeted file or example is
  fine. Go back to leaving it alone once it passes.
- A docs-only or comment-only change does not need a run. Say so instead.

Always say which specs ran and what the result was. If something is new and
unrun, say that plainly rather than implying it passed.

`rubocop` is cheap; run it freely.

### Running specs locally

The RSpec suite uses the local PostgreSQL test database on `localhost:5432`.
In a sandboxed Codex session, grant the command local-service/elevated access
before the first invocation; do not run an unprivileged attempt first because
the sandbox will fail during Rails boot with `Operation not permitted` before
any examples load. Clear the development URL so Rails cannot point the test
environment at the development database:

```bash
env -u DATABASE_URL TEST_DATABASE_URL=postgresql://localhost/project_red_crm_test \
  RAILS_ENV=test bundle exec rspec
```

Run the suite once after the feature is complete and report the exact
example/failure count.

## CI and deployment monitoring

It is okay to inspect and watch the GitHub Actions run for this repository,
including deployment progress, with `gh run view` or `gh run watch`. When a run
fails, inspect the failed job logs before making another push. A successful
deployment should be verified on the production host when the task includes a
production change.

## Specs

Write specs as you go rather than at the end, but keep them proportionate:

- **Always cover access control.** Who is kept out matters more than who is let
  in, so write the negative case first. Anything touching a policy, a policy
  scope, or a membership grant needs a spec.
- **Always cover data migrations that touch existing rows**, and anything where
  getting it wrong is silent rather than loud.
- Cover the critical path of a feature, not every branch of it.
- Do not add specs for straightforward serialization, or for framework
  behaviour that Rails already guarantees.

## Authorization

Authorization is enforced by default: `Api::V1::BaseController` runs
`verify_authorized` on every non-index action and `verify_policy_scoped` on
every index. A new controller action must call `authorize` (or
`skip_authorization` with a reason) or it raises.

- Every policy answers the same question set: `view?`, `create?`, `update?`,
  `destroy?`, `manage?`. `show?` and `index?` alias `view?`.
- `manage?` means "may change how this resource works for everyone" —
  configuring columns, granting access, archiving — as distinct from `update?`,
  which means "may edit this record".
- Policies serialize `#capabilities` onto records and into the auth payload so
  the portal can ask what a user may do instead of re-deriving it from `role`.
  These are rendering hints; the server still authorizes every request.
- New API controllers inherit `Api::V1::BaseController`. Inheriting
  `ApplicationController` directly opts out of enforcement and fails
  `spec/requests/authorization_coverage_spec.rb`.

## Boards

Workflow columns and tasks belong to a `Board`, not directly to an
organization. Column keys are unique per board, and `workflow_tasks.listing_id`
is nullable — whether a task needs a property is `Board#requires_listing`.
Client-visible tasks additionally require `Board#client_visible`.

## Media and attachment URLs

- Listing media may use its configured public CDN URL; board and chat
  attachments are private and use separate storage boundaries.
- Serializers must expose authorized API-relative `preview_path` and
  `download_path` values. Never expose a storage key, construct an S3 URL in a
  React component, or point a browser tag at a private bucket directly.
- Preview routes must authorize the parent record before streaming from the API
  origin. Download routes may redirect to a short-lived signed URL only after
  the same authorization check.
- The UI must resolve serialized paths through `apiUrl`, `mediaAssetUrl`, and
  `mediaAssetDownloadUrl`; credentialed API previews must also be recognized by
  `apiMediaNeedsCredentials` when used in `<img>` or `<video>` tags.
- When adding an attachment type, update the storage boundary, serializer,
  API/UI types, URL helper, renderer, and a negative access-control spec
  together. Do not repeat the old raw-path/CDN-host mistake.

## Conventions

- Money is integer cents; rates are basis points.
- Controllers scope through `Current.organization` and Pundit.
- Comments explain why a non-obvious choice was made, not what the line does.
- Follow `rubocop-rails-omakase`.
