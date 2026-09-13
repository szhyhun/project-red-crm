# Background-job business workflows and Interactors

This is the refactoring plan for ProjectRed's background business workflows.
The safety baseline and first extraction slices are now in the repository. The
remaining phases continue from that working baseline rather than introducing a
parallel compatibility path.

The implementation convention is documented in [`docs/interactors.md`](../interactors.md):
all action and Organizer classes live under `app/interactors`, integration
actions are grouped below `app/interactors/integrations/<provider>/actions`,
and future cross-domain automation composition belongs below
`app/interactors/automations/organizers`.

The plan has four equal outcomes:

1. Make business workflows easier to read, debug, and reason about by giving
   them one consistent action shape.
2. Make failures visible at the exact interactor step that failed, including
   safe inputs, outputs, warnings, and error codes.
3. Reuse small, well-tested interactors inside multiple organizers so tests
   cover each business rule once and organizers focus on composition.
4. Simplify the codebase: remove stale services, duplicate orchestration,
   dead branches, obsolete compatibility paths, and abstractions that do not
   earn their complexity. Fewer lines is useful, but removing competing paths
   and reducing cognitive load is the real measure of success.

The design is based on the [Interactor pattern described by FullStack
Labs](https://www.fullstack.com/labs/resources/blog/encapsulating-ruby-on-rails-business-logic-with-interactors):
a plain Ruby object exposes one `call` entry point, carries explicit inputs and
outputs in a context, and fails through a consistent mechanism. An Interactor
is a business-action boundary, not a replacement for Resque, Active Job, a
database transaction, or a model validation.

This is not a promise to convert every class into an interactor or to minimize
line count mechanically. A one-line database operation should remain simple.
The pattern is justified when an action has multiple business steps, more than
one entry point, retries, partial failure, authorization boundaries, or a need
to compose the same rules in different workflows.

## Rules for the refactor

1. Jobs remain thin infrastructure adapters. They load the durable record,
   call one interactor or organizer, and let the queue retry or record the
   failure.
2. Interactors own business decisions and state transitions. A job must not
   contain a second implementation of the same workflow.
3. Every interactor has a small, documented context contract. Inputs are
   required explicitly; outputs use stable names; failures have a safe error
   code and a human-readable message.
4. An organizer is used only where the steps are a real ordered business
   transaction. Independent work stays in separate interactors rather than
   becoming one large “do everything” context.
5. Transactions surround the records that must commit together. External HTTP,
   S3, email, Action Cable, and queue calls happen outside the database
   transaction or through an outbox/idempotency boundary.
6. Every retry is idempotent. The interactor receives a durable idempotency key
   or finds the existing record before creating another one.
7. Authorization stays at the controller/service boundary. Interactors do not
   bypass Pundit or accept another organization's records.
8. A job's intermediate state is visible, but every normal return, handled
   failure, retry exhaustion, and watchdog timeout ends in a terminal state.
9. Every extracted interactor must replace an old path. After the new path is
   proven, delete the old service methods, branches, compatibility aliases, and
   unused helpers rather than leaving both implementations in the repository.

## Current job-to-interactor map

The first implementation slice is now in place:

- `ApplicationInteractor` provides a small context with typed failures and
  step records; `ApplicationOrganizer` composes reusable actions.
- Media verification, Aryeo media copying, notification delivery, message
  notification, stale-import recovery, and import orchestration now run
  through Interactor entry points.
- Workflow execution is split into action Interactors for parent tasks, child
  tasks, placements, deliverable links, user assignment, and group assignment.
  The old monolithic `Workflows::Runner` path has been removed.
- Queue jobs are adapters: they load the durable record, call the Interactor,
  and preserve retry/error semantics.

Aryeo resource mapping now lives in the focused `Aryeo::ResourceImporter`
service instead of one file per provider method. `Conversations::PurgeExpired`
is already the single retention action. Deliverable materialization remains a
small service called inside the approval transaction until it has an
independent caller or a real multi-step failure boundary; wrapping it only to
rename the class would add complexity without removing a competing path.
Order approval itself now uses `Orders::ApproveOrder` plus
`Workflows::Trigger`.

The next application boundaries are also implemented:

- `Workflows::MoveTask` owns canonical task movement, shared placements,
  deliverable state, completion timestamps, and transition activity.
- `Conversations::PublishMessage` owns message persistence, media references,
  `last_message_at`, and post-commit notification enqueueing.
- `MediaReviews::Submit` owns review closure, draft-comment publication,
  request-changes transitions, and the account conversation notification.
- `ClientMemberships::Invite` owns invited-user creation, membership state, and
  the invitation audit event.
- `Payments::ProcessStripeWebhook` owns Stripe event idempotency and the
  payment/invoice transition; signature verification remains in the webhook
  controller.
- `ClientPortal::CreateListing` owns customer booking creation and its audit
  event.
- `ClientPortal::RequestReschedule` owns appointment request, event, and
  listing activity persistence.
- `ClientPortal::CreateChangeRequest` owns the legacy compatibility message,
  selected-media references, deliverable transition, activity, and post-commit
  notification.
- `Orders::Create` owns catalog price resolution, order-item snapshots, order
  totals, and order-created activity.

The old service implementations and the `Orders::EnqueueWorkflow` wrapper were
deleted after the focused specs passed. No controller retains a second path for
these transitions.

| Current entry point | Proposed business action | Durable result |
| --- | --- | --- |
| `AryeoImportJob` | `Integrations::Aryeo::Organizers::ImportOrganizer` | `IntegrationImportRun` is completed, completed with errors, or failed |
| `AryeoMediaCopyJob` | `Integrations::Aryeo::Actions::CopyMedia` | `MediaAsset` and `ExternalRecord` are copied or failed idempotently |
| `Aryeo::ImportWatchdogJob` | `Integrations::Aryeo::Actions::FailStaleImports` | Abandoned imports are failed and their connections are released |
| `BoardWorkflowJob` | `Workflows::ExecuteRun` organizer | Workflow steps and task placements are synchronized |
| approval controller boundary | `Orders::Approve` organizer | Order approval and deliverable/task materialization are idempotent |
| workflow task mutation controllers | `Workflows::MoveTask` | Canonical task state and every authorized placement stay synchronized |
| order approval workflow step | `Workflows::Trigger` | One idempotent run per order/workflow/version |
| `MediaAssets::VerifyUploadJob` | `MediaAssets::VerifyUpload` | Asset becomes ready or records a safe processing failure |
| conversation message controller | `Conversations::PublishMessage` | Message and references commit before notification enqueue |
| media review submit controller | `MediaReviews::Submit` | Review outcome and request-changes state commit before notification |
| client membership invite controllers | `ClientMemberships::Invite` | User/membership/audit transition is atomic |
| Stripe webhook controller | `Payments::ProcessStripeWebhook` | Payment event is idempotent and invoice state is reconciled |
| portal listing creation | `ClientPortal::CreateListing` | Draft booking request and activity are created together |
| portal appointment mutation | `ClientPortal::RequestReschedule` | Appointment request, event, and activity are atomic |
| order creation controller and callers | `Orders::Create` | Catalog pricing, item snapshots, totals, and activity are one action |
| `Notifications::DeliverJob` | `Notifications::Deliver` | Delivery becomes delivered or failed with retry metadata |
| `Conversations::NotifyJob` | `Conversations::Notifier` | Participants, unread state, and Action Cable notification are consistent |
| `Conversations::RetentionJob` | `Conversations::PurgeExpired` | Expired messages and private attachments are removed by policy |

The terminal-state, media, notification, workflow, approval, import, and
retention boundaries are implemented. Workflow execution and notification/media
actions are decomposed into reusable steps. Task movement, message publication,
review submission, membership invitation, and payment webhook reconciliation are
now application actions. Portal booking and reschedule mutations are also
application actions. Aryeo import orchestration is kept
as a visible Organizer chain while provider-specific mapping remains grouped in
`app/services/aryeo/resource_importer.rb`; each extraction removes a competing
path rather than adding a wrapper around unchanged code.

## Observability and composition contract

An organizer is a visible sequence of named steps, not a hidden call chain.
Each step must expose:

- a stable step name;
- the minimal input identifiers, never secrets or full provider payloads;
- created or changed record IDs as output;
- warnings separately from failures;
- a safe error code, exception class, and human-readable message;
- start, completion, and duration timestamps;
- whether the step was skipped, retried, or completed.

The durable workflow/run record should retain this step history when the
workflow is user-visible or retryable. Logs should include the organizer ID,
step name, organization ID, and business record ID so a failure can be traced
from the UI to Rails logs without reproducing the whole workflow. This is what
makes an organizer easier for a person or a language model to inspect: the
control flow is explicit and the failure boundary is named.

Shared interactors are tested at the business-rule level once. Organizers then
test only sequencing, branching, context hand-off, and failure propagation.
They should not repeat every internal assertion already covered by the shared
interactor. This keeps scenario coverage strong while avoiding a combinatorial
test suite.

## Simplification and stale-code audit

Every phase includes a cleanup pass. Before extracting a workflow, inventory:

- duplicate service objects that perform the same action under different names;
- controller branches that bypass the existing service;
- job-specific copies of retry, status, or authorization logic;
- dead compatibility fields and aliases;
- unreachable provider branches and title-based inference;
- serializers, routes, and UI clients that no longer have a caller;
- tests that describe behavior the product no longer supports.

For each candidate, record one of: keep, merge, deprecate with a removal date,
or delete. A refactor is not complete while the old and new paths can both
mutate the same records. The acceptance checklist for every phase includes a
repository search proving that removed names and obsolete branches have no
live callers, plus a focused test proving the replacement path owns the
behavior.

### Current audit decisions

Keep these as services unless their boundary changes:

- `Aryeo::Client`, `Aryeo::RemoteMediaCopy`, storage adapters, and payment
  provider clients are protocol adapters.
- `Aryeo::ImportSession` and `Aryeo::ResourceImporter` are grouped provider
  parsing/mapping services. Splitting each endpoint or field into an action
  would recreate the stale import structure that was just removed.
- `Orders::DeliverableMaterializer` is a transactional persistence helper,
  not an Organizer step by itself. It becomes an action only if its failure or
  retry boundary becomes independently observable.
- `Invoices::Creator`, `MediaReviews::Workspace`, pricing resolvers, and
  presenters are a small idempotent helper or read-side code; wrapping them
  would add indirection without a business transition.

The portal change-request compatibility mutation is now an explicit action with
one transaction and post-commit notification. The active portal review path
remains `MediaReviews::Submit`; the compatibility action exists only for older
clients. Do not create micro-actions for individual order items, fields, or
validation helpers.

## Import organizer shape

The eventual Aryeo organizer should have a context similar to:

```ruby
Integrations::Aryeo::Organizers::ImportOrganizer.call(
  run: integration_import_run,
  client: client,
  resources: resources,
  conflict_resolution: conflict_resolution
)
```

Its steps should be explicit:

1. `Integrations::Aryeo::Actions::StartImport` locks the run, sets `running`, records `started_at`,
   and starts the heartbeat.
2. `Integrations::Aryeo::Actions::ImportSelectedCollections` imports the selected collections and records
   endpoint coverage, source IDs, partial errors, and progress.
3. `Integrations::Aryeo::Actions::ReconcileImportedDelivery` links imported orders, services, media,
   and deliverables without inventing Aryeo package relationships.
4. `Integrations::Aryeo::Actions::CompleteImport` chooses `completed` versus
   `completed_with_errors`, stores final counts, and reconnects the integration.
5. `Integrations::Aryeo::Actions::FailImport` is the single failure transition used by exceptions,
   retry exhaustion, and the watchdog. It records the error and completion time
   exactly once.

`Aryeo::ImportSession` and `Aryeo::ResourceImporter` keep provider mechanics
outside the Organizer. `ImportSelectedCollections` owns its private resource
import sequence; there is no nested resource Organizer. The Organizer is only
the top-level chain, and provider helpers stay grouped in services and are
tested there.

## Implementation sequence

### Phase 1 — safety baseline

- Keep the current import heartbeat/watchdog and terminal-state specs green.
- Capture a short baseline of the current job/service graph and identify the
  duplicate or stale paths that the phase is expected to remove.
- Add an integration-run state transition matrix: pending → running → each
  terminal state, with no terminal → running transition.
- Add a structured error code for endpoint failure, record validation failure,
  media-copy failure, and stale-worker failure.
- Add a run-level idempotency spec proving a retry does not duplicate external
  records, variants, media, deliverables, or workflow runs.

### Phase 2 — Aryeo interactors

- Keep the repository's small dependency-free `ApplicationInteractor` and
  `ApplicationOrganizer` unless a concrete missing capability justifies a gem;
  adding `interactor-rails` merely for naming would violate the simplification
  goal.
- Extract start/fail/complete first; these are small and remove duplicate state
  transitions before moving import mapping logic.
- Keep catalog, customer/team, listing/media, order, appointment, and task
  mapping together in `Aryeo::ResourceImporter` unless one of them becomes a
  separately reused business workflow. Do not create one action file per Aryeo
  endpoint or private mapping helper.
- Keep local date filtering and `MAIN`/`ADDON` classification in the catalog
  and resource interactors. Never infer packages from names or descriptions.
- Keep remote media copy as a separate retryable job/interactor because it has a
  different network and storage failure boundary.
- Delete the old monolithic importer branches only after characterization and
  replacement specs pass; do not leave a second “legacy import” path behind.

### Phase 3 — order and workflow automation

- Keep `Orders::Approve` and `Workflows::ExecuteRun` as organizers with one
  idempotency key per order or workflow run. Extract deliverable materialization
  only if it becomes a separately reused or multi-step workflow; otherwise the
  existing small transactional service is the simpler boundary.
- Give each action a result object/context containing created IDs and warnings;
  do not make later steps query loosely related titles.
- Keep board authorization and placement synchronization in the workflow
  interactor, with negative specs for cross-organization and unauthorized-board
  access.

### Phase 4 — media, chat, and notifications

- Extract media verification/publish actions with explicit storage boundary and
  API-relative URL contracts.
- Extract message publication so database persistence, unread counters, and
  Action Cable broadcast have a documented order and retry behavior.
- Extract retention as a policy-driven organizer that deletes database rows and
  private storage objects together, with a safe retry result.
- Remove duplicate URL, storage, unread-count, and notification paths once the
  shared interactors own those contracts.

## Required specs before each extraction

- A unit spec for success, validation failure, and retry/idempotency behavior.
- A job spec proving the queue adapter invokes the interactor and terminal
  state is written when the interactor fails.
- A request/scenario spec for the user-visible critical path.
- A negative authorization spec wherever an interactor receives a record ID or
  organization-scoped input.
- A storage/media spec that checks serialized paths and the final URL boundary,
  not merely that an object exists.
- A logging/observability spec for handled partial failures so a green worker
  process cannot hide `completed_with_errors`.
- A cleanup assertion or repository search showing that the replaced stale
  path is gone.

## Completion criteria

The refactor is complete when each job is a thin queue adapter, each business
workflow has one reusable `call` path, all state transitions are centralized,
retries are idempotent, and the full RSpec suite covers both success and the
failure/authorization boundaries. The codebase must have fewer competing
paths, fewer obsolete branches, and a smaller workflow surface to understand,
not merely more wrapper classes. No controller, job, or model should contain a
second competing implementation of an interactor's business action, and every
deleted path must be backed by evidence that it has no remaining callers.

## Current implementation status

The planned extraction pass is implemented. The application now has explicit
Interactor/Organizer boundaries for import lifecycle and delivery
reconciliation, order creation and approval, workflow execution and movement,
conversation publication and retention, media review submission, membership
invitation, payment webhooks, and portal booking/reschedule/change-request
mutations.

The remaining service objects are intentional boundaries: provider/storage
adapters, read-side presenters and resolvers, invoice record creation, and the
portal change-request compatibility action. Those are not hidden duplicate
workflow paths.
