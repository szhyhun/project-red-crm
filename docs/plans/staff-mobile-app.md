# Staff mobile app, and the on-site upsell prompt

Status: **idea only**. Nothing here is built, and nothing in the API depends on
it yet. This file records the intent so the shape of it is not lost, and so new
work on orders, packages and notifications stays compatible with it.

## Who it is for

The people who go to the property: photographers, videographers, drone pilots.
They already exist as organization users with production roles and already carry
appointments, listing assignments and workflow tasks. The app is their view of
that work, on the phone, rather than a second system:

- their own account and their own schedule, not the whole organization's;
- the listing they are driving to, with the address, the customer and the
  access notes;
- their tasks for that listing, and somewhere to mark the work done;
- notifications when they are assigned, when an appointment moves, and when a
  customer asks for something on a listing they shot.

## The part that earns the app: what was ordered, and what to sell next

When the photographer arrives, the app shows **what the customer actually
ordered for this listing** — the order, its items, and for a package, the
services inside it. That alone prevents the common failure of shooting the
wrong scope.

Then the app proposes the upsell, on the spot, in words the photographer can
say out loud:

- the add-ons that go with what was ordered — a twilight shoot with a
  waterfront listing, a reel with a video package, a floor plan with photos;
- why each one fits, in one short line, so the pitch is not invented at the
  door;
- a discount the photographer may offer because the customer already bought
  the package, with the price already worked out;
- a way to add it to the order there and then, so the customer agrees once
  rather than being chased by email afterwards.

The message is sent to the photographer when the shoot is confirmed, so they
arrive knowing the pitch: "this customer ordered the Signature package. Suggest
a twilight set and a vertical reel; they get 15% off either because the package
is already on the order."

## Mileage, the car, and the rest of what a trip costs

The phone is the only thing that is actually at the property, so it is the only
honest place to record what getting there cost:

- **Distance per trip**, captured per appointment: the drive out, between two
  shoots in a day, and home again. Either odometer readings the photographer
  types or a distance the phone measured, with the typed number winning,
  because a reading someone stands behind beats a track that lost signal.
- **A rate per kilometre** per organization, so distance becomes money without
  anyone doing arithmetic at the kerb.
- **Other trip costs with a photo of the receipt**: fuel, parking, a ferry, a
  toll, a lockbox key, a parking ticket if the organization pays it.
- **Separate from what the customer is charged.** `TravelFee` already prices
  distance *to* the customer (flat, percentage or per kilometre, against a
  planned staff `HomeBase`). What the employee is *paid back* is a different
  number, and conflating them would quietly bill a customer for a detour.
- **Reimbursement as pay, not as an expense system.** `PayrollItem` already
  belongs to a listing, an optional order and a team member, carries cents, a
  title, notes and a `draft → submitted → paid` lifecycle. A mileage claim and
  a receipt are payroll items of their own kind; what is missing is the kind,
  the distance and the attached photo, not a new ledger.

That gives the three sides what each needs from the same record: the employee
sees what they are owed and when it was paid, the employer sees cost per shoot
and per person next to the revenue on that listing, and the customer is only
ever shown the travel fee that was actually quoted to them.

## What else the app could carry

Roughly in the order each pays for itself:

- **Time on site**: start and finish, so hours worked sit beside the shoot
  rather than in somebody's memory. The same two taps drive hourly pay.
- **The shot list for what was ordered**: a package's components become a
  checklist, so a missing floor plan is caught at the property instead of in
  the edit.
- **Upload status from the field**: how much of today's card has reached us,
  which is the question the office asks most and the one the photographer can
  least easily answer.
- **Access and arrival facts**: lockbox or gate instructions, where to park,
  who to meet, the pets. Treated as sensitive: visible for the appointment,
  not browsable as a directory, and not kept after delivery.
- **Conditions and incidents**: weather that forced a reshoot, a staging crew
  running late, damage noticed on arrival — with a photo. This is what settles
  a dispute about a reshoot charge weeks later.
- **The customer's yes, captured on the spot**: an approval for an add-on, a
  reshoot, or a scope change the photographer and customer agreed in person.
- **Their own numbers**: shoots this week, pay owed, pay paid, mileage
  year-to-date. A contractor who can see this stops emailing to ask.
- **Route for the day**: next job, travel time, and the warning when two
  appointments cannot both be made.
- **Equipment taken out and returned**, if the organization lends bodies,
  lenses or drones.

## What already exists to build on

- **Packages and their contents**: `ProductComponent` joins a package product
  to the service products inside it, so "what is in this order" is already
  answerable.
- **Orders on a listing**: `Order`, `OrderItem` and `OrderDeliverable` carry
  what was bought, at what price, and what is owed. `Order#ordered_by` now
  records the person who placed it.
- **Appointments**: who is assigned, when, and for which listing, including the
  customer's own blocked-photographer list.
- **Pay per shoot**: `PayrollItem` already ties money owed to a listing, an
  order and a team member, with a `draft → submitted → paid` lifecycle.
- **Distance pricing**: `TravelFee` prices flat, percentage or per-kilometre
  travel to the customer; a staff `HomeBase` is already planned for the
  distance it measures from.
- **Notifications on three channels**: email, SMS and browser push already run
  off one matrix of events; a phone app adds a device channel rather than a new
  pipeline.
- **Discounts**: `Coupon` holds fixed or percentage, time-bounded, redemption-
  limited discounts, and orders snapshot discount cents. An on-site offer is a
  coupon with a short life, not a new pricing concept.
- **Deterministic recommendations** are already named in the staged roadmap
  (phase 4 of `docs/plan.md`); this is where they would be used first.

## What has to be decided before building it

- **Whose phone, and what it may keep.** A personal phone holding lockbox
  codes, customer addresses and photos needs a rule for what is cached, for
  how long, and what happens when someone leaves.
- **What counts as proof of a trip.** A typed odometer reading, a measured
  track, or either; and whether a claim needs an approval before it becomes
  pay.
- **Who may discount, and by how much.** A photographer offering a price is a
  pricing decision made outside the office. It needs a ceiling per role, an
  audit line for every offer, and a rule for whether the customer's team
  pricing plan already accounts for it.
- **Whether the customer confirms.** An add-on the photographer taps through
  changes what the customer owes. Either the customer approves it in the portal
  (slower, safer) or the photographer records their verbal yes (faster, and
  disputable).
- **Where the suggestions come from.** A hand-written table of
  "package → suggested add-ons" per organization is honest and predictable.
  Anything learned from history needs enough orders to be worth trusting.
- **Native or web.** The portal is already a responsive web app. Push, camera
  and offline notes are the arguments for native; nothing else here is.
- **Offline.** Properties have poor signal. Reading the order offline matters
  more than writing, so the order and its scope should be cached per
  appointment.

## Why it is not next

It depends on work that is either unfinished or unproven: recommendations exist
only as a roadmap line, and discount authority has no model yet. It is worth
keeping in view, because the data it needs is being built anyway.

The cheapest first slice, if it is picked up: the schedule, the ordered scope
for the listing, and mileage with a receipt photo. That is useful on its own,
needs no new pricing authority, and every later piece hangs off it.
