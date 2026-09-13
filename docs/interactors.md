# Interactors and business workflows

ProjectRed uses Interactors as the application boundary for business actions.
The goal is not to turn every one-line CRUD operation into a class. The goal
is to give every multi-step business operation one readable, testable, and
observable path.

This rule applies to new code and to refactors of existing workflows.

## Directory layout

```text
app/interactors/
├── application_interactor.rb
├── application_organizer.rb
├── automations/
│   └── organizers/
├── conversations/
├── integrations/
│   └── aryeo/
│       ├── actions/
│       └── organizers/
├── client_memberships/
├── client_portal/
├── media_assets/
├── media_reviews/
├── notifications/
├── orders/
├── payments/
└── workflows/
```

Provider mapping and transport services live under `app/services/aryeo/`.
Tests mirror the application boundary under `spec/interactors/`. Job specs stay
under `spec/jobs/`, request specs stay under `spec/requests/`, and low-level
provider/storage adapter specs stay under `spec/services/`.

The shared implementation is intentionally dependency-free:

- `app/interactors/application_interactor.rb` provides `Context` and typed
  `Failure` values.
- `app/interactors/application_organizer.rb` composes ordered Interactors and
  records step outcomes.
- We do not add `interactor-rails` merely for naming. A dependency is justified
  only when the current context contract cannot provide a required capability.

## Which layer owns what?

| Layer | Owns | Does not own |
| --- | --- | --- |
| Controller | HTTP parsing, authorization, one action call, rendering | Business transactions, retries, queue orchestration |
| Interactor | One business action, state changes, transactions, side effects | HTTP details or authorization bypasses |
| Organizer | Ordered composition and branching between actions | A second implementation of an action |
| Model | Associations, validations, enums, database invariants | Multi-record workflows and provider calls |
| Policy | Authorization and organization scope | Pricing, workflow execution, storage writes |
| Query/serializer | Read-side composition and safe response shape | Mutating records |
| Adapter service | HTTP, S3, email, and payment-provider protocol | Deciding the CRM business outcome |

Provider-specific mapping is not automatically an Interactor. `Aryeo::Client`
owns HTTP and pagination, `Aryeo::ImportSession` owns import-run state and
provider parsing helpers, and `Aryeo::ResourceImporter` owns the grouped Aryeo
resource-to-ProjectRed mapping. Do not create one Interactor for every client
method, payload field, product variant, or media record. Extract a separate
Interactor only when the step is a meaningful business action with its own
failure/retry boundary or when it is reused by another Organizer.

Keep a model validation when the rule must be true regardless of who calls it.
For example, `PricingPlan` should reject two owners from a console, import,
request, or job. Put “resolve the customer price, create the order, record
activity, and enqueue fulfillment” in an Interactor because that is a business
workflow.

## An action Interactor

An action has one public entry point: `.call`. It receives explicit inputs,
puts outputs in the context, and uses `context.fail!` for a handled business
failure.

Live example: `Integrations::Aryeo::Actions::StartImport` in
`app/interactors/integrations/aryeo/actions/start_import.rb`:

```ruby
result = Integrations::Aryeo::Actions::StartImport.call(run: import_run)

return if result[:skipped] # the run was already terminal
raise result.failure if result.failure?
```

The action owns the transition to `running`, records the heartbeat, and marks
the integration as importing. It does not perform HTTP requests or decide how
every provider resource is mapped.

The provider mapping stays in one focused service rather than becoming one
file per Aryeo endpoint:

```ruby
Aryeo::ResourceImporter.call(
  session: import_session,
  name: :listings,
  payload: provider_listing
)
```

The resource service may have private helpers such as `import_product` or
`import_media_asset`; those helpers do not need separate files because they
are provider mapping details. The Interactor boundary wraps the meaningful
workflow around that service and remains independently observable.

Other live action boundaries follow the same rule:

```text
Workflows::MoveTask
  canonical task + selected placement + shared placements + deliverables

Conversations::PublishMessage
  message + media references + last_message_at → notification enqueue

MediaReviews::Submit
  review state + draft comments + request-changes transition → notification

ClientMemberships::Invite
  invited user + account membership + audit event

Payments::ProcessStripeWebhook
  webhook idempotency + payment/invoice transition + receipt scheduling

ClientPortal::CreateListing
  customer booking request + listing activity

ClientPortal::RequestReschedule
  appointment request + appointment event + listing activity

ClientPortal::CreateChangeRequest
  legacy compatibility message + selected media references + deliverable
  transition + activity + notification

Orders::Create
  catalog pricing + order items + totals + order activity
```

These are actions because each one owns a durable business transition and has
more than one record or side effect that must be reasoned about together. Their
private parsing, validation, and notification helpers stay inside the action;
they are not split into files merely because a method has a name.

## Action or Organizer?

Use an action when one business intent has several implementation steps. Keep
those steps as private methods on the action when they are not independently
reused or observed:

```ruby
class ImportSelectedCollections < ApplicationInteractor
  def call
    session = build_session
    import_selected_collections(session)
    session.heartbeat!(force: true)
  end

  private

  def import_selected_collections(session)
    # fetch, filter, import, and finalize are private details of this action
  end
end
```

Use an Organizer when the workflow is a meaningful ordered chain whose steps
deserve their own result, failure boundary, telemetry, or reuse. The canonical
shape is the same as the Interactor gem's documented example:

```ruby
class ImportOrganizer < ApplicationOrganizer
  organize StartImport, ImportSelectedCollections, ReconcileImportedDelivery, CompleteImport
end
```

Do not turn an action into an Organizer only to create sub-actions for its
private helpers. Do not turn every provider endpoint or client method into an
Interactor. This distinction is a project rule and is part of code review.

Do not add namespace-flavored aliases such as `catalog_value` delegating to
`value` or `task_time_value` delegating to `time_value`. Call the generic
helper directly. A session method is justified only when it adds lookup,
normalization, persistence, state, or another real provider-specific rule.

## Context, outputs, and failures

The context is a small mutable result carrier, not a global state store.
Inputs and outputs should be named and minimal:

```ruby
result = SomeAction.call(order:, actor:)

if result.failure?
  Rails.logger.warn("#{result.failure.code}: #{result.failure.message}")
  raise result.failure.original_error || result.failure
end

order = result.fetch(:order)
```

Use stable, safe error codes. Do not put passwords, API keys, raw uploads, or
complete provider payloads in a failure context or log line.

```ruby
context.fail!(
  code: "media_copy_failed",
  message: error.message,
  original_error: error,
  external_record_id: external_record.id,
  asset_id: asset.id
)
```

`original_error` is for retry behavior and tests; `code` is for durable
observability and UI; `message` is for a human-readable diagnostic. A handled
warning is not a failure: return a successful context with an explicit warning
or `skipped: true` output.

## Organizers and automations

An Organizer is a named sequence of actions. It should read like the business
workflow, not like a controller with hidden branches.

Live example: `Orders::Approve` in `app/interactors/orders/approve.rb`:

```ruby
class Approve < ApplicationOrganizer
  organize ApproveOrder, Workflows::Trigger
end
```

`ApproveOrder` owns the transaction and idempotent deliverable materialization.
`Workflows::Trigger` runs only after approval succeeds. Neither job nor controller
duplicates those steps.

The Aryeo boundary is organized under
`Integrations::Aryeo::Organizers::ImportOrganizer`. Its visible chain is:

```text
StartImport
  → ImportSelectedCollections
      → Aryeo::ResourceImporter (private action step)
  → imported delivery reconciliation
  → CompleteImport

job exception        → FailImport
watchdog timeout     → FailStaleImports
```

`ImportSelectedCollections` owns the private resource-import sequence:
conflict lookup, provider mapping, external-record archival, and count/error
recording. Those steps are not separate Interactors because they are not
independently reused, observed, or retried. There is deliberately no nested
`ImportResource` Organizer.

Future automation composition belongs under `app/interactors/automations`:

```text
app/interactors/automations/organizers/
  create_production_work_organizer.rb
  submit_media_review_organizer.rb
```

An automation organizer may compose actions from other domains:

```ruby
module Automations
  module Organizers
    class CreateProductionWork < ApplicationOrganizer
      organize Orders::ApproveOrder, Workflows::ExecuteRun
    end
  end
end
```

Only add this organizer when the product has a real ordered automation. Do not
copy an action into an automation namespace or create an organizer for one
database write.

## State transitions and terminal results

Every durable workflow has an explicit state matrix. Intermediate states may be
visible while work is active, but normal completion, handled failure, retry
exhaustion, and watchdog recovery must all be terminal.

```text
IntegrationImportRun:
  pending → running → completed
                    → completed_with_errors
                    → failed
  completed / completed_with_errors / failed → unchanged on retry
```

`IntegrationImportRun#error_code` records a stable category such as
`endpoint_failure`, `record_validation_failure`, `media_copy_failed`, or
`stale_worker`. Human-readable details remain in `error_details`.

For a new stateful workflow:

1. Write the allowed transition table first.
2. Lock the durable record before deciding whether a retry is a no-op.
3. Set start, heartbeat/lease, and intermediate state together.
4. Make each external side effect idempotent or give it a durable intent key.
5. Centralize failure and watchdog transitions in one action.
6. Add a spec proving no terminal state returns to `running`.

## Transactions and external effects

Keep records that must agree in one transaction. Keep network, S3, email,
Action Cable, and queue calls outside that transaction or behind a durable
intent/idempotency boundary.

For example:

- `Orders::ApproveOrder` commits the approved order, deliverables, and activity
  together.
- `Workflows::Trigger` runs after that commit and uses the workflow run's
  idempotency key.
- `Conversations::PublishMessage` commits the message and media references
  before it attempts to enqueue Action Cable notification work.
- `MediaReviews::Submit` commits the review outcome and any request-changes
  transition before it publishes the account conversation notification.
- `Notifications::PrepareDelivery` leases a delivery row;
  `Notifications::SendDelivery` performs email outside the lease transaction
  and records success/failure.
- `Conversations::Notifier` broadcasts only after the message is persisted and
  the queue job has loaded it again.

Never make Redis or S3 availability decide whether a successfully persisted
user message disappears. Persist first, then retry the notification or storage
side effect.

## Controllers and jobs

Controllers should be thin:

```ruby
def approve
  order = policy_scope(Order).find(params[:id])
  authorize order, :update?
  result = Orders::Approve.call(order:, actor: current_user)
  raise result.failure.original_error || result.failure if result.failure?
  render json: { order: serialize(order.reload) }
end
```

Jobs should load the durable record, call one action or Organizer, and preserve
queue retry semantics:

```ruby
def perform(import_run_id)
  run = IntegrationImportRun.find(import_run_id)
  result = Integrations::Aryeo::Organizers::ImportOrganizer.call(run:)
  raise result.failure.original_error || result.failure if result.failure?
end
```

Controller actions use the same shape after Pundit has resolved the records:

```ruby
result = Conversations::PublishMessage.call(
  conversation:, author: current_user, body:, media_assets: authorized_assets
)
raise result.failure.original_error || result.failure if result.failure?
message = result.fetch(:message)
```

Authorization remains outside the action because HTTP policy scope decides what
the current user may reference. The action still validates organization and
relationship invariants through the models before committing.

Authorization stays in the controller/policy boundary. An Interactor still
checks organization ownership and record relationships when it receives a
record from another internal caller; it must never use an Interactor as a way
around Pundit.

## Testing rule

Every new action or organizer gets the smallest test set that proves its real
risk:

- action unit spec: success, validation/handled failure, and idempotency;
- organizer spec: order, branch, context hand-off, and failure propagation;
- job spec: the queue adapter calls the action and preserves the error;
- request/scenario spec: the user-visible path;
- negative authorization spec when an organization or record ID crosses the
  boundary;
- storage/provider spec when a URL, object, or external call is involved;
- a search or deletion assertion proving the replaced path is gone.

Do not test Rails' own `belongs_to` behavior. Do test silent failure modes such
as duplicate deliverables, duplicate workflow runs, cross-organization media,
terminal jobs left in `running`, and warnings incorrectly reported as success.

## Current extraction audit

The current audit intentionally leaves these as services:

- `Aryeo::Client`, `Aryeo::RemoteMediaCopy`, storage classes, and payment
  provider clients are protocol adapters; they do not decide CRM state.
- `Aryeo::ImportSession` and `Aryeo::ResourceImporter` keep provider parsing
  and grouped mapping together. Creating an action for every endpoint or
  payload field would recreate the duplication the import refactor removed.
- `Orders::DeliverableMaterializer` is a small transactional persistence helper
  called by approval and imported-delivery reconciliation. It should become an
  action only if it gains an independent retry/failure boundary, not merely to
  rename it.
- `Invoices::Creator`, `MediaReviews::Workspace`, pricing resolvers, and
  presenters are respectively an idempotent record helper, a read-side query,
  and read/formatting code. Wrapping them would add indirection without an
  observable workflow step.
- `ClientPortal::CreateChangeRequest` owns the legacy compatibility mutation:
  it creates the account conversation inside the same transaction as the
  message, media references, deliverable transition, and activity, then queues
  notification only after the transaction commits. The current portal does not
  use this path; it uses `MediaReviews::Submit`, but the compatibility endpoint
  has the same explicit business boundary.

## Simplification rule

Before adding an Interactor, search for every existing caller and competing
implementation. Reuse the existing policy, parser, storage adapter, or model
invariant. After the new action owns the behavior, delete the old branch and
update its focused specs. The desired result is fewer competing paths and less
stale code—not a larger collection of wrappers.
