# Listings implementation checklist

This checklist is derived from the supplied Listings specification. A checked item means the current Rails API and CRM UI provide the described usable behavior. A partial item is deliberately left unchecked and labelled `PARTIAL`; structural placeholders do not count as complete.

## Listings dashboard

- [x] Views section is displayed at the top of Listings.
- [x] All Listings view is available and shows a live count.
- [x] Unscheduled Listings view is available and shows listings without a non-cancelled appointment.
- [x] Listings Awaiting Fulfillment view is available and shows a live count.
- [x] Awaiting Fulfillment includes undelivered listings and listings with a non-fulfilled order.
- [x] Search field uses the specified `Search listings by address or client name...` placeholder.
- [x] Search supports property address.
- [x] Search supports every attached client name, not only the primary client.
- [x] Search supports every attached client email.
- [x] Search supports exact Listing ID and Order ID.
- [x] Search supports MLS number.
- [x] Filters button opens the full filtering drawer.
- [x] Delivery Status filter includes all, delivered, and undelivered.
- [x] Zillow Showcase Platform Listing filter includes no filter, yes, and no.
- [x] Listing Status filter includes all listing statuses.
- [x] Delivered After and Delivered Before date filters are available.
- [x] Order Payment Status supports any, unpaid, partially paid, and paid.
- [x] Order Fulfillment Status supports any, unfulfilled, partially fulfilled, and fulfilled.
- [x] Order Status filter is available.
- [x] Order Items is a searchable multi-select populated from active products.
- [x] Tags is a searchable multi-select populated from listing and order tags.
- [x] Order Created After and Order Created Before date filters are available.
- [x] Appointment Status filter is available.
- [x] Appointment Request Status filter is available.
- [x] Appointment Team Members is a searchable multi-select and covers primary and additional appointment team members.
- [x] Appointment Quick Filters section is separate from the main appointment filters.
- [x] Quick filter: 2 Days Ago.
- [x] Quick filter: Yesterday.
- [x] Quick filter: Today.
- [x] Quick filter: Tomorrow.
- [x] Quick filter: Future.
- [x] Quick filter: Past.
- [x] Quick filter: No Appointments.
- [x] Appointment After and Appointment Before custom date filters are available.
- [x] Multiple filters combine and update the result query.
- [x] Active filters appear as individually removable chips.
- [x] Reset Filters clears all selected filters.
- [x] Page order follows Views, Search/Filters, active chips, and Listings Results.
- [x] Operational states are visible without opening each listing.
- [x] Grid/List display switch is on the right of the Listings toolbar.
- [x] Grid/Card View is available and is the default for a new user.
- [x] List View is available.
- [x] The user's selected display mode persists through a saved preference.
- [x] Grid cards show the explicitly selected cover image, falling back to the first ready image.
- [x] Grid cards show a neutral placeholder when no property image exists.
- [x] Grid cards show address and city/postal code.
- [x] Grid cards show delivery, payment, listing, and fulfillment statuses.
- [x] Grid cards show appointment date/time or Not scheduled.
- [x] Grid cards show assigned team member or Unassigned.
- [x] Grid cards show ordered services or the order-item count.
- [x] Grid cards have a working Open listing action and the whole card opens the listing.
- [x] Grid is responsive: three desktop columns, two tablet columns, one mobile column.
- [x] List View shows Property, Client, Appointment, Team Member, Order, Fulfillment, Delivery, Payment, Created, and Actions columns.
- [x] List View shows Not scheduled when no appointment exists.
- [x] The entire list row opens the listing.
- [x] List View additional-actions ellipsis opens a working Open/Copy Address menu.
- [x] Grid and List icon buttons have a clear active state.
- [x] Switching display mode preserves search, selected view, filters, sort, results per page, and current page where practical.
- [x] Pagination is clamped when a new query returns fewer pages.
- [x] Sorting and results-per-page controls are available.
- [x] 8. Saved Views management drawer with create/edit/delete and per-user drag ordering.
- [x] 9. Create/edit Saved View with personal/team access.
- [x] 10. Saved View filter configuration.
- [x] 11. Saved View actions: reset, preview/apply, save.
- [x] 12. Saved View behavior as reusable filter presets.
- [x] 13. Saved View visibility remains separate from listing authorization.

## Listing details workspace

- [x] 1. Listing header with full address, delivery/payment/fulfillment badges and quick actions.
- [x] 2. Multiple customers on one listing with Add Customer.
- [x] 3. Customer quick card/popover, contact details, marketing visibility, and view/edit actions. Customer contact edits are organization-scoped.
- [x] 4. Listing actions: Deliver, Download, Settings, More Actions.
- [x] 5. Continuous two-column desktop workspace, single-column mobile.
- [x] 6. Collapsible Orders section with multiple orders and Add Order.
- [x] 7. Payroll section and Create Pay Run Item.
- [x] 8. Collapsible Appointments with full summary and Add Appointment.
- [x] 9. Internal Customer Notes card.
- [x] 10. Rich-text Internal Listing Notes card.
- [x] 11. Property Details and map link.
- [x] 12. Categorized Media workspace: Images, Videos, Floor Plans, 3D Content, Files.
- [x] 13. Custom Fields card and configuration.
- [ ] 14. Marketing section: property details/status, websites, materials. `PARTIAL: basic property site and materials workflow exists; full editor, domains, analytics, and generation remain`
- [x] 15. Chronological Activity Log.
- [ ] 16. Consistent collapsible-card behavior, status badges, and operational priority. `IN PROGRESS`

## Orders

- [x] 1. Compact collapsible order summary with payment/fulfillment status.
- [x] 2. Complete order actions menu.
- [x] 3. Expanded order details in place.
- [x] 4. Add/remove order tags.
- [x] 5. Complete order item details, descriptions, options, quantities, and prices.
- [x] 6. Item actions: edit, create payroll item, cancel.
- [x] 7. Add Product Item drawer with search/filter.
- [x] 8. Add Custom Item workflow.
- [x] 9. Add Order under the current listing.
- [x] 10. Full Create Order drawer with multiple items.
- [x] 11. Pricing summary with discounts, tax, total, and a separate fee line.
- [ ] 12. Existing/one-off coupons.
- [x] 13. Order tax editing and recalculation.
- [x] 14. Payments and outstanding balance.
- [x] 15. Multiple orders per listing.
- [ ] 16. Derived payment and fulfillment status logic. `PARTIAL`
- [x] 17. Edit existing order and fulfillment statuses; item editing remains incomplete.
- [x] 18. Order-item price override while preserving catalog price.
- [x] 19. Cancel item without deleting order history.
- [x] 20. Confirmed soft cancellation of an order.
- [x] 21. Active product catalog search data exists; drawer filters remain incomplete.
- [x] 22. Custom order items.
- [x] 23. Percentage/fixed discount calculation.
- [x] 24. Separate tax and fee lines.
- [x] 25. Payment history and partial payments.
- [x] 26. Secure payment collection is connected to invoices; order-level partial collection remains incomplete.
- [x] 27. Send Payment Reminder.
- [x] 28. One invoice per selected order with send/pay operations; download remains incomplete.
- [x] 29. Additional order creation inherits listing and customer.
- [x] 30. Order/appointment association.
- [x] 31. Order/order-item source tracing for media.
- [x] 32. Order fulfillment and listing delivery are separate states.
- [ ] 33. Full order Activity Log coverage.
- [ ] 34. Fine-grained financial/destructive permissions.
- [x] 35. Complete compact-to-expanded order UX.

## Payroll / Pay Run Items

- [x] 1. Payroll card and empty state.
- [x] 2. Create Pay Run Item form.
- [x] 3. Team member relationship and selector data.
- [x] 4. Order relationship.
- [x] 5. Title.
- [x] 6. Currency amount.
- [x] 7. Optional submitted date; drafts are not payroll-eligible.
- [ ] 8. Validated create actions and disabled state.
- [x] 9. Pay Run Item display with team member, amount, and status filtering.
- [x] 10. Draft, Submitted, Included in Pay Run, Paid, Cancelled states.
- [x] 11. Optional Order Item association and prefill-ready schema.
- [x] 12. Multiple Pay Run Items per order/listing.
- [x] 13. Payroll totals by status.
- [x] 14. Edit Pay Run Item API and UI.
- [x] 15. Soft cancellation API and UI.
- [ ] 16. Fine-grained payroll permissions.
- [x] 17. Payroll Activity Events.
- [x] 18. Required Listing/Order/Team Member data relationships.
- [ ] 19. End-to-end payroll workflow UI.

## Customer experience feedback

- [x] 1. Delivery creates one feedback request for every attached listing customer and queues a feedback email that links to the signed-in client portal.
- [x] 2. Three rating questions: Delivery, Service, Final Media.
- [x] 3. Optional comment.
- [x] 4. Compact four-step rating controls in the client portal.
- [x] 5. Submitted feedback displays a thank-you state in the client portal.
- [ ] 6. Listing/order/customer associations. `PARTIAL: appointment/team snapshots are not stored on feedback`
- [x] 7. Listing workspace feedback summary.
- [x] 8. Compact summary state.
- [x] 9. Expanded feedback card in the client portal.
- [x] 10. Needs Attention state for negative answers.
- [x] 11. Customer-card feedback summary.
- [x] 12. Customer feedback history.
- [x] 13. Customer latest/count/trend overview.
- [x] 14. Secondary grid/list indicator.
- [x] 15. Internal follow-up state is set to Needs Attention for any rating of 1 or 2; follow-up management UI remains incomplete.
- [x] 16. Aggregate reporting.
- [x] 17. Recent feedback requiring attention.
- [x] 18. V1 remains the specified simple three-question flow.

## Delivery performance

- [x] 1. Listing delivery timeline using appointment completion and delivery timestamps.
- [x] 2. Delivery timestamp and first customer portal-view timestamp are tracked automatically.
- [x] 3. Appointment-complete to customer-delivery metric.
- [x] 4. Customer first-view timestamp.
- [ ] 5. Product-level delivery metrics.
- [ ] 6. Package-level delivery metrics.
- [ ] 7. Monthly delivery comparison.
- [ ] 8. Product/package delivery targets.
- [ ] 9. Late-delivery identification.
- [ ] 10. Business Report delivery block/trend.
- [ ] 11. Delivery-time distribution buckets.
- [x] 12. Listing workspace turnaround status.
- [x] 13. Automatic calculation without manual input.

## Appointments

- [x] 1. Separate card per appointment.
- [x] 2. Date, time, calculated duration, assignee, notes. `UI needs expanded presentation`
- [x] 3. Reschedule, Postpone, Cancel, Customer Reschedule actions.
- [x] 4. Existing appointment can be rescheduled with audit history.
- [x] 5. Appointment scheduling history.
- [x] 6. Postponed state.
- [x] 7. Confirmed soft cancellation preserving history.
- [x] 8. Customer Reschedule Page. `Implemented as a customer-portal modal with current appointment context and requested date/time fields.`
- [x] 9. Duration can be edited via start/end; dedicated duration UI remains incomplete.
- [x] 10. Multiple Appointment Team Members.
- [x] 11. Team Member management controls.
- [x] 12. Appointment Items.
- [x] 13. Appointment Item management.
- [x] 14. Order Item to Appointment Item relationship.
- [x] 15. Add Appointment.
- [x] 16. Multiple appointments per listing.
- [x] 17. Full appointment statuses.
- [x] 18. Completion timestamp. `SCHEMA ADDED`
- [x] 19. Appointment team member relationship; reporting remains incomplete.
- [x] 20. Correct position in continuous Listing workspace.

## Media

- [x] 1. Five categorized media groups with counts.
- [x] 2. Independent collapsible cards with category counts and empty states.
- [x] 3. Customer visibility per category/asset.
- [x] 4. Add media action.
- [x] 5. Upload modal/drawer. `Device batch upload and external video/3D link forms share one media drawer.`
- [ ] 6. Device, Link, Camera, Dropbox, Google Drive, Google Photos, OneDrive sources. `DEVICE ONLY`
- [x] 7. Upload progress is shown with a spinner, aggregate byte progress, file count, and file names for multi-file device uploads. Background processing status remains separate.
- [ ] 8. Complete Images workspace.
- [x] 9. Image drag reordering and cover image.
- [x] 10. Image/media bulk selection and delete action.
- [x] 11. Video file and video link support.
- [x] 12. Video metadata, optional thumbnail URL, visibility, ordering.
- [ ] 13. Floor-plan uploads and formats. `PARTIAL`
- [ ] 14. Linked/embedded 3D provider content.
- [ ] 15. General Files workspace. `PARTIAL`
- [x] 16. Internal assets remain inaccessible to customers when hidden.
- [x] 17. Live category counts.
- [x] 18. Preview/download/rename/replace/hide/delete item actions.
- [x] 19. Category-aware direct drag-and-drop reordering.
- [x] 20. Upload processing states exist with retry for failed verification.
- [x] 21. Delivery readiness by category.
- [x] 22. Order/order-item source trace.
- [x] 23. One Listing Media area supports media from multiple orders.
- [x] 24. Customer delivery policy respects final/ready/visible assets.
- [ ] 25. Fine-grained media permissions.
- [ ] 26. Media Activity Log coverage.
- [x] 27. Complete in-listing media-management workflow. `Upload, batch progress, preview, metadata, poster, visibility, replace, retry, reorder, and delete are available.`

## Marketing

- [ ] 1. Complete Property Details and Status fields, status schedule, and autocomplete.
- [x] 2. Property Website card with status and basic actions; full behavior incomplete.
- [x] 3. Customer visibility for property websites.
- [ ] 4. Branded property website.
- [ ] 5. Unbranded / MLS-friendly website.
- [x] 6. Publish/deactivate lifecycle. `PARTIAL`
- [ ] 7. Custom listing domain connection flow.
- [ ] 8. Property Website editor.
- [x] 9. Public website view path. `PARTIAL`
- [ ] 10. Basic website analytics.
- [ ] 11. Future analytics-ready data.
- [x] 12. Marketing Materials card/count/Create.
- [x] 13. Marketing Materials customer visibility.
- [x] 14. Marketing Material creation workflow.
- [x] 15. New material titles can be prefilled from listing address; richer template reuse remains incomplete.
- [ ] 16. Status-based marketing generation.
- [ ] 17. Promote Your Listing extension point.
- [ ] 18. Marketing visibility logic.
- [ ] 19. Marketing Activity Log coverage.
- [ ] 20. Final independent collapsible Marketing structure.
- [ ] 21. Listing remains the source of truth for all marketing outputs.

## Deferred Later

These items are intentionally deferred and should remain on the roadmap without blocking the current Listings workspace work.

### Reporting

- [ ] Product/package delivery metrics.
- [ ] Monthly comparisons.
- [ ] Delivery targets and late-delivery detection.
- [ ] Business report trends and distribution buckets.

### Marketing

- [ ] Complete property details and status management.
- [ ] Branded and unbranded property sites.
- [ ] Domain connection.
- [ ] Website editor.
- [ ] Analytics.
- [ ] Marketing generation and activity tracking.
