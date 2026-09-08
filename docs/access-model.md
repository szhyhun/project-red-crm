# Access model

## Tenant rule

Every user belongs to exactly one organization. A login is never shared across
multiple media agencies. This keeps tenant scoping straightforward and avoids
cross-agency visibility through a contractor account.

## Roles

| Role | Primary access |
| --- | --- |
| `platform_owner` | Platform-level access, separate from ordinary organization operations. |
| `organization_admin` | Organization setup, staff/client invitations, catalog, and operations. |
| `manager` | Listings and production operations. |
| `production_staff` | Internal production workflow access. |
| `client_admin` | Customer-facing data for its linked client account. |
| `client_member` | Customer-facing data for its linked client account. |

`ClientMembership` links a client user to one or more client accounts within the
same organization. It does not grant access to unrelated customer accounts.

## Authorization boundaries

- Internal users use organization-scoped operational endpoints.
- Client users are rejected from the internal dashboard and appointment index.
- Client listing details expose only customer-visible tasks and omit internal
  appointments and staff assignments.
- Client users can only see final, ready media from their own listings.
- Client users may download that delivered media, but cannot upload, replace,
  reorder, hide, or delete `MediaAsset` records. Delivery changes remain a
  staff-side operation.
- Customer conversation access requires both the client account relationship and
  a conversation membership; staff-only messages are withheld.
- Public property-site data includes only final, ready media.

## Session behavior

The API uses Devise session cookies plus Rails CSRF protection. The UI asks for
a CSRF token before `POST`, `PATCH`, or `DELETE` requests. Sign-out clears the
current surface's cached CSRF token and ends that surface's Rails session.

The staff CRM and customer portal use separate encrypted session cookies,
selected from the validated browser origin, so an admin and a customer can be
signed in simultaneously in one browser. They do not need a new `portal` role.
A customer account is recognized by its existing
`client_portal.view` capability, while internal accounts use the staff
capabilities. The shared UI renders the customer surface only at the portal
origin and the staff surface only at the CRM origin; an account on the wrong
surface is shown a hand-off screen instead of loading the other product's data.
