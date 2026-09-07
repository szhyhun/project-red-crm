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
listing details, receive delivery notifications, and submit feedback. A
property site can expose the published listing and its final ready media as a
public-facing page.

Raw or failed production media remains internal. Customers see only media that
the agency has marked ready and made customer-visible.

## Conversations and chat retention

ProjectRed supports internal team conversations and customer conversations.
People see a conversation only when they are allowed to participate in it.
Messages support rich text and file attachments. A message can be edited or
deleted, and a top-level message can have replies one level deep.

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
