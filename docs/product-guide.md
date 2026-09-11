# ProjectRed CRM product guide

This is the plain-language overview of what ProjectRed CRM does for a media
agency and its customers. It describes product behavior and configuration, not
the Rails API or deployment details. Engineering notes live in the other
documents in this directory.

## What ProjectRed CRM is

ProjectRed CRM gives a media agency one workspace for customer relationships,
property work, production, delivery, communication, and billing. Staff use the
CRM to move work from a new request to a completed delivery. Customers see only
the listings, files, tasks, invoices, and conversations that belong to them.

## People and access

An organization has one private workspace. Organization administrators manage
the workspace and invite people. Managers run day-to-day production. Production
staff work on assigned listings, appointments, and tasks. Customer users see
their own client account and listings through the customer portal.

Access is limited by both the organization and the specific customer account.
A customer cannot see another customer's listings, private production work, or
staff-only conversations.

## Where people work

Staff use the main CRM navigation:

- **Dashboard** for today's production and items needing attention;
- **Listings** for customer and property workspaces;
- **Boards** for production tasks;
- **Calendar** for appointments;
- **Catalog**, **Orders**, and **Billing** for services, orders, and invoices;
- **Messages** for team and customer conversations; and
- **Team & access** and **Integrations** for administration.

Customers use the customer portal. Their main screen is **Your listings**;
each listing contains its progress, appointments, delivery files, invoices,
feedback, and listing-linked updates.

## How-to workflows

The normal job flow is: create the listing, add the services and order,
schedule the appointment, complete production, collect payment, deliver the
finished work, and gather feedback. The workflows below explain who does each
part and where the hand-off happens.

### Admin or manager: create a listing and prepare the work

1. Open **Listings** and choose **New listing**.
2. Enter the client name and email, property address, city, province, and
   optional brokerage and square footage.
3. Choose **Create listing**. ProjectRed creates the customer workspace and
   opens the new listing workspace.
4. In **Orders and invoices**, choose **Create order**, select the catalog
   products or variants, set quantities, and choose whether the order is paid
   now or invoiced after delivery.
5. Add an appointment, assign the photographer/editor or other team members,
   and set the appointment time on the listing or Calendar page.
6. Add or update production tasks on the appropriate board. Link each task to
   the listing so staff can move between the task and the property workspace.

The listing workspace is the source of truth for that job. Start there when a
customer asks about a specific property instead of creating a separate
organization-wide conversation.

### Admin or manager: invoice the listing

1. Open the listing and expand **Orders and invoices**.
2. If the order does not have an invoice, choose **Draft invoice**.
3. Check the order total and choose **Send invoice**. The invoice is sent to
   the customer's email address and active portal users.
4. The customer can pay from the invoice in the customer portal. The invoice
   and listing payment status update after the payment provider confirms the
   payment.

If an invoice cannot be sent, the listing needs a customer email address. An
invoice cannot be created twice for the same order.

### Customer: pay for a listing

1. Sign in to the customer portal and open the relevant listing under **Your
   listings**.
2. Find the invoice in the **Invoices** section and choose **Pay now**.
3. Complete the secure payment form and submit the payment.
4. Return to the listing to see the updated invoice and payment status.

ProjectRed does not store card details. The payment form is hosted by the
configured payment provider. If there is no **Pay now** button, the invoice is
already paid, is not payable yet, or has not been issued by the agency.

### Customer: review delivered media and ask for a change

1. Open the listing in the customer portal and choose **View delivered media**.
2. Choose **Review media**. ProjectRed opens a review window with one section
   for every published service or media category: photography, video, floor
   plan, tour, or another file group. The button appears whenever there is
   customer-visible media; it is never shown disabled.
3. On the exact file that needs attention, choose the round **+** button. Write
   the comment and choose **Add to review**. Repeat this for as many files as
   needed; comments remain together as one draft review instead of becoming a
   pile of unrelated chat messages.
4. Choose an outcome at the bottom:
   - **Comment** sends the review as feedback without reopening production.
   - **Request changes** sends the selected feedback to the production team and
     creates production work for the reviewed media. If the files came from an
     order, the related internal work is also updated; an order deliverable is
     not required.
   - **Approve delivery** records that you explicitly accepted the delivered
     files.
5. Choose **Submit review**. The production team receives a notification in
   the account conversation, while the detailed file-by-file discussion stays
   in the review workspace.

If you leave without submitting, the review remains a draft and can be
continued later. A listing with customer-visible media but no review record is
treated as accepted by default; the explicit **Approve delivery** outcome is
available when the customer wants an auditable approval. Uploading and
successfully processing media makes it available to the customer—staff do not
need to mark an internal order deliverable as delivered first.

Staff see the submitted review in the listing workspace and in **Messages**.
They can reply to each file-specific thread, resolve comments, replace the
affected delivery media, and publish a new delivery revision. The review keeps
the original files and comments together, so the customer and production team
can see what changed and why. General questions and new files still belong in
the account conversation.

After delivery, the customer can also submit the separate **Feedback** form.
Feedback rates delivery, service, and final media; it is not a replacement for
an in-progress change request.

### Staff: start or continue the correct conversation

Customers do not create chats. A staff member starts a customer-visible thread
for one or more customer accounts, and the customer replies to it from the
portal.

To start one:

1. Open the listing workspace and use its conversation or updates section.
2. Choose **New customer conversation**. The customer account is preselected
   when the dialog was opened from a listing, but the conversation itself is
   account-wide rather than attached to a listing.
3. Give the conversation a name, confirm that it is **Client-visible**, select
   one or more customer accounts, and select the internal team participants.
   Customer portal users for the selected accounts are added automatically.
4. Start the conversation. It may begin empty; send the first reply whenever
   there is an update to share. Listing, service, or selected-media context is
   added to individual messages when relevant.

If the customer account already has a conversation, open it and choose
**Reply** instead of creating another thread. Listing and service context stays
on the relevant messages. A customer conversation is readable by the customer
account, so internal production notes belong in the task or an internal team
conversation.

For an internal team chat, open **Messages**, choose the **+** action in the
Team section, select **Internal team**, give it a name, and select the team
participants. You are included automatically. Internal conversations are
organization-wide and never shown in the customer portal; they may also begin
empty.

### Video editor or production staff: process assigned work

1. Open **Boards** and select the board used by the team. Filter or scan for
   tasks assigned to you.
2. Open the task to read the description, checklist, due date, priority,
   labels, and linked listing.
3. Move the task between workflow columns as work progresses. Use the checklist
   for concrete production steps and task comments for internal discussion.
4. Attach working files or completed media to the task when the team needs to
   review them. Keep customer-facing delivery files in the listing's delivery
   area, where the agency can mark them ready and visible.
5. When a customer requests a change, update the relevant task or create a
   focused task, assign it, and reply in the account conversation with the
   listing context so the customer can follow the outcome.

Do not put internal editing notes in a client-visible conversation. If a task
is linked to a listing, use the listing link in the task to check the customer,
order, appointment, and delivery context before marking work complete.

### Staff: handle an appointment change requested by a customer

Customers open an appointment in their listing and choose **Request a different
time**. They provide a new start and end time plus an optional note. Staff
review the request in the listing or Calendar view, then approve, decline, or
reschedule it. The customer sees the request status in the portal.

## Listings and customer workspaces

A listing is the main workspace for a property and its order. It can include:

- customer and property details;
- listing status, notes, and custom fields;
- products and order items;
- appointments and assigned staff;
- production tasks and checklists;
- delivery media and a customer-facing property site; and
- customer feedback and delivery history.

Listings move through the agency's workflow, from draft and booking through
production, review, and delivery. A listing can still be delivered when there
is no customer email address; the CRM simply cannot send that customer email.

## Production boards

Boards organize internal work visually. An organization can have multiple
boards, and each board can have its own:

- workflow columns and their order;
- shared labels and label colors; and
- board members and access rules.

Tasks on a board can have a title, description, priority, assignee, due date,
listing, checklist, labels, attachments, and customer-visible setting. Teams
can move and reorder tasks between columns. Task details include a chronological
activity and comment area, rich text, attachments, and replies to top-level
comments. Replies cannot create another level of replies.

## Appointments and calendar

Appointments belong to a listing and can include one or more team members.
Staff can schedule, edit, reassign, move, cancel, and delete appointments. The
calendar prevents overlapping active appointments for the same staff member.

## Catalog, orders, and invoices

The catalog contains products, packages, services, variants, and add-ons. An
organization can configure prices and supporting rules such as taxes, coupons,
travel fees, and customer-specific pricing plans.

Orders keep the selected product variants and the calculated totals. Invoices
can be drafted from an order and sent to the customer's email address and
active portal users. Payment collection can be enabled through the configured
payment provider; card details are handled by that provider and are not stored
in ProjectRed. Square support and provider-selection controls are future product
work, not a current customer setting.

## Delivery and customer portal

Staff can attach final delivery media to a listing and publish it to the
customer portal. Customers can view the files that are ready for them, access
listing details, receive delivery notifications, review each delivered service,
and submit feedback. A property site can expose the published listing and its
final ready media as a public-facing page.

The portal presents each ordered service as its own expandable delivery card,
with the service name, type, status, dates, files, downloads, and available
actions together. **Review media** opens the file-by-file review workspace;
customers can comment with the `+` marker on individual assets and submit one
outcome for the review. Photos, videos, floor plans, tours, and files that were
imported or uploaded before they were linked to an order remain visible in
separate media-category cards instead of being collapsed into one generic file
list. Those unlinked files can be downloaded or discussed in the account
conversation; the structured review workflow is available only on real ordered
deliverables.

Raw or failed production media remains internal. Customers see only media that
the agency has marked ready and made customer-visible.

## Conversations and chat retention

ProjectRed supports internal team conversations and customer conversations.
People see a conversation only when they are allowed to participate in it.
Messages support rich text and file attachments. A message can be edited or
deleted, and a top-level message can have replies one level deep.

Customer conversations belong to the customer account. A message can carry
the relevant listing and delivered service as context, which keeps payment,
appointment, production, and change-request discussions in the right property
workspace without creating a separate chat for every service. Organization-wide
team chats are for internal work that does not belong to one listing.

Chat history has a retention policy on each conversation. The default is two
months. A staff member with permission can choose:

| Setting | History kept for |
| --- | --- |
| Two months | 60 days |
| Six months | 180 days |
| One year | 365 days |
| Forever | No automatic expiry |

When a finite retention period expires, the CRM removes old messages and their
attached chat files. The conversation itself, its members, and newer messages
remain available. Retention is configured per conversation, so changing one
conversation does not change the policy for other chats.

## Aryeo import

An organization administrator can run a manual Aryeo import when the
integration is connected. The import can include team users, clients, customer
teams, products and variants, listings, orders, appointments, and tasks.

Listings, orders, and appointments can be limited by an inclusive **from** and
**to** date. ProjectRed applies those dates to the timestamps it receives, so
the import still works when Aryeo's own date filters are incomplete. Team
users, clients, customer teams, and products import in full when selected.

When listings are imported, their available media and related records are
requested as part of the import. Related customers, teams, orders, and
appointments can be imported as dependencies even if their separate checkboxes
were not selected. An import can either skip records already imported from
Aryeo or overwrite the existing imported copy. It never overwrites native
ProjectRed records.

Aryeo imports are started manually; they do not run on a recurring schedule.
The import history shows what was selected, which date range was used, how many
records were imported or skipped, and any media or endpoint errors.

## Configuration at a glance

| Area | What an organization can configure |
| --- | --- |
| Access | Staff roles, customer membership, board membership, and conversation membership |
| Boards | Boards, columns, shared labels, colors, ordering, and visibility |
| Production | Task priorities, assignees, due dates, checklists, and customer visibility |
| Catalog | Products, variants, add-ons, prices, taxes, coupons, travel fees, and customer pricing |
| Delivery | Ready media, customer visibility, property-site publishing, and feedback workflows |
| Chat | Conversation members and per-conversation retention period |
| Aryeo | Imported resource groups, date range for date-sensitive records, and conflict policy |

## Planned or deployment-dependent features

The product is still being expanded. Depending on the deployment, the following
may be unavailable or still under development:

- Square payment processing and payment-provider selection;
- direct large-file uploads and automatic media transcoding;
- recurring Aryeo synchronization;
- advanced reporting and analytics; and
- marketing campaign planning and automation.

When a feature is not available in the CRM interface, it should be treated as
planned work rather than assumed to be enabled.
