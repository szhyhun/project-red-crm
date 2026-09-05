# Working in this repository

## Do not run the test suite or watch CI

Do not run `rspec`, `bundle exec rspec`, or `rails test`. The maintainer runs
the suite. Write the specs, say which files are new or changed and that they
have not been run, and leave it there.

Do not watch CI either — no `gh run watch`, and no polling `gh run list` for a
run to finish. Push, say what the push will trigger, and stop. The maintainer
reads the result.

`rubocop` is fine to run; it is cheap.

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

## Conventions

- Money is integer cents; rates are basis points.
- Controllers scope through `Current.organization` and Pundit.
- Comments explain why a non-obvious choice was made, not what the line does.
- Follow `rubocop-rails-omakase`.
