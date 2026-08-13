# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_12_210000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "activity_events", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "actor_id"
    t.string "event_type", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_activity_events_on_actor_id"
    t.index ["organization_id", "created_at"], name: "index_activity_events_on_organization_id_and_created_at"
    t.index ["organization_id"], name: "index_activity_events_on_organization_id"
    t.index ["subject_type", "subject_id"], name: "index_activity_events_on_subject"
  end

  create_table "appointment_events", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.bigint "actor_id"
    t.string "event_type", null: false
    t.jsonb "changeset", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_appointment_events_on_actor_id"
    t.index ["appointment_id", "created_at"], name: "index_appointment_events_on_appointment_id_and_created_at"
    t.index ["appointment_id"], name: "index_appointment_events_on_appointment_id"
  end

  create_table "appointment_items", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.bigint "order_item_id"
    t.string "title", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_appointment_items_on_appointment_id"
    t.index ["order_item_id"], name: "index_appointment_items_on_order_item_id"
  end

  create_table "appointment_team_members", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "team_member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id", "user_id"], name: "index_appointment_team_members_on_appointment_id_and_user_id", unique: true
    t.index ["appointment_id"], name: "index_appointment_team_members_on_appointment_id"
    t.index ["user_id"], name: "index_appointment_team_members_on_user_id"
  end

  create_table "appointments", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "assigned_user_id"
    t.string "status", default: "scheduled", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "calendar_color"
    t.string "request_status", default: "not_requested", null: false
    t.bigint "order_id"
    t.datetime "completed_at"
    t.index ["assigned_user_id"], name: "index_appointments_on_assigned_user_id"
    t.index ["listing_id"], name: "index_appointments_on_listing_id"
    t.index ["order_id"], name: "index_appointments_on_order_id"
    t.index ["organization_id", "request_status"], name: "index_appointments_on_organization_id_and_request_status"
    t.index ["organization_id", "starts_at"], name: "index_appointments_on_organization_id_and_starts_at"
    t.index ["organization_id"], name: "index_appointments_on_organization_id"
    t.exclusion_constraint "organization_id WITH =, assigned_user_id WITH =, tsrange(starts_at, ends_at, '[)'::text) WITH &&", where: "(assigned_user_id IS NOT NULL) AND ((status)::text <> 'cancelled'::text)", using: :gist, name: "no_overlapping_staff_appointments"
  end

  create_table "catalog_sync_runs", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "source", null: false
    t.string "status", default: "pending", null: false
    t.integer "products_seen", default: 0, null: false
    t.integer "products_created", default: 0, null: false
    t.integer "products_updated", default: 0, null: false
    t.jsonb "unmapped_products", default: [], null: false
    t.jsonb "errors", default: [], null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_catalog_sync_runs_on_organization_id"
  end

  create_table "client_accounts", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "kind", default: "agent", null: false
    t.string "email"
    t.string "phone"
    t.string "brokerage_name"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_client_accounts_on_organization_id_and_name"
    t.index ["organization_id"], name: "index_client_accounts_on_organization_id"
  end

  create_table "client_memberships", force: :cascade do |t|
    t.bigint "client_account_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_account_id", "user_id"], name: "index_client_memberships_on_client_and_user", unique: true
    t.index ["client_account_id"], name: "index_client_memberships_on_client_account_id"
    t.index ["user_id"], name: "index_client_memberships_on_user_id"
  end

  create_table "conversation_memberships", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "participant", null: false
    t.datetime "last_read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "user_id"], name: "index_conversation_memberships_on_conversation_and_user", unique: true
    t.index ["conversation_id"], name: "index_conversation_memberships_on_conversation_id"
    t.index ["user_id"], name: "index_conversation_memberships_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id"
    t.bigint "client_account_id"
    t.string "kind", default: "internal", null: false
    t.string "subject"
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_account_id"], name: "index_conversations_on_client_account_id"
    t.index ["listing_id"], name: "index_conversations_on_listing_id"
    t.index ["organization_id", "kind", "last_message_at"], name: "idx_on_organization_id_kind_last_message_at_fcb0d57e64"
    t.index ["organization_id"], name: "index_conversations_on_organization_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "client_account_id", null: false
    t.bigint "listing_id"
    t.bigint "order_id"
    t.string "number", null: false
    t.string "status", default: "draft", null: false
    t.string "currency", default: "cad", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.integer "balance_due_cents", default: 0, null: false
    t.date "due_on"
    t.datetime "sent_at"
    t.datetime "paid_at"
    t.string "payment_provider"
    t.string "provider_invoice_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "discount_cents", default: 0, null: false
    t.integer "fee_cents", default: 0, null: false
    t.string "fee_label", default: "Service fee", null: false
    t.index ["client_account_id"], name: "index_invoices_on_client_account_id"
    t.index ["listing_id"], name: "index_invoices_on_listing_id"
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["organization_id", "number"], name: "index_invoices_on_organization_id_and_number", unique: true
    t.index ["organization_id", "status"], name: "index_invoices_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_invoices_on_organization_id"
  end

  create_table "listing_assignments", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.bigint "user_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["listing_id", "user_id", "role"], name: "index_listing_assignments_on_listing_user_role", unique: true
    t.index ["listing_id"], name: "index_listing_assignments_on_listing_id"
    t.index ["user_id"], name: "index_listing_assignments_on_user_id"
  end

  create_table "listing_custom_fields", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.string "name", null: false
    t.text "value"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["listing_id", "position"], name: "index_listing_custom_fields_on_listing_id_and_position"
    t.index ["listing_id"], name: "index_listing_custom_fields_on_listing_id"
  end

  create_table "listing_customers", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.bigint "client_account_id", null: false
    t.boolean "primary", default: false, null: false
    t.boolean "marketing_visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_account_id"], name: "index_listing_customers_on_client_account_id"
    t.index ["listing_id", "client_account_id"], name: "index_listing_customers_on_listing_id_and_client_account_id", unique: true
    t.index ["listing_id"], name: "index_listing_customers_on_listing_id"
  end

  create_table "listing_feedbacks", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.bigint "client_account_id", null: false
    t.bigint "order_id"
    t.integer "delivery_rating"
    t.integer "service_rating"
    t.integer "media_rating"
    t.text "comment"
    t.string "follow_up_status", default: "none", null: false
    t.datetime "requested_at"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_account_id"], name: "index_listing_feedbacks_on_client_account_id"
    t.index ["listing_id", "submitted_at"], name: "index_listing_feedbacks_on_listing_id_and_submitted_at"
    t.index ["listing_id"], name: "index_listing_feedbacks_on_listing_id"
    t.index ["order_id"], name: "index_listing_feedbacks_on_order_id"
    t.index ["organization_id", "follow_up_status"], name: "idx_on_organization_id_follow_up_status_a201545642"
    t.index ["organization_id"], name: "index_listing_feedbacks_on_organization_id"
  end

  create_table "listing_notes", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.bigint "author_id", null: false
    t.string "note_type", default: "listing", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "body_format", default: "plain", null: false
    t.index ["author_id"], name: "index_listing_notes_on_author_id"
    t.index ["listing_id", "note_type", "created_at"], name: "index_listing_notes_on_listing_id_and_note_type_and_created_at"
    t.index ["listing_id"], name: "index_listing_notes_on_listing_id"
    t.index ["organization_id"], name: "index_listing_notes_on_organization_id"
  end

  create_table "listing_view_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "display_mode", default: "grid", null: false
    t.jsonb "saved_view_order", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_listing_view_preferences_on_user_id", unique: true
  end

  create_table "listings", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "client_account_id", null: false
    t.string "status", default: "draft", null: false
    t.string "public_slug"
    t.string "address_line_1", null: false
    t.string "address_line_2"
    t.string "city"
    t.string "province"
    t.string "postal_code"
    t.string "country", default: "CA", null: false
    t.integer "square_feet"
    t.integer "bedrooms"
    t.decimal "bathrooms", precision: 4, scale: 1
    t.datetime "scheduled_at"
    t.datetime "delivered_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "delivery_status", default: "undelivered", null: false
    t.boolean "zillow_showcase", default: false, null: false
    t.string "mls_number"
    t.string "tags", default: [], null: false, array: true
    t.datetime "customer_first_viewed_at"
    t.index ["client_account_id"], name: "index_listings_on_client_account_id"
    t.index ["customer_first_viewed_at"], name: "index_listings_on_customer_first_viewed_at"
    t.index ["organization_id", "delivery_status"], name: "index_listings_on_organization_id_and_delivery_status"
    t.index ["organization_id", "public_slug"], name: "index_listings_on_organization_id_and_public_slug", unique: true
    t.index ["organization_id", "status"], name: "index_listings_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_listings_on_organization_id"
    t.index ["tags"], name: "index_listings_on_tags", using: :gin
  end

  create_table "marketing_materials", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.bigint "created_by_id"
    t.string "material_type", null: false
    t.string "title", null: false
    t.string "status", default: "draft", null: false
    t.boolean "customer_visible", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_marketing_materials_on_created_by_id"
    t.index ["listing_id", "status"], name: "index_marketing_materials_on_listing_id_and_status"
    t.index ["listing_id"], name: "index_marketing_materials_on_listing_id"
    t.index ["organization_id"], name: "index_marketing_materials_on_organization_id"
  end

  create_table "media_assets", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id"
    t.bigint "uploaded_by_id"
    t.string "kind", default: "final", null: false
    t.string "status", default: "pending", null: false
    t.string "storage_key"
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size"
    t.integer "width"
    t.integer "height"
    t.integer "duration_seconds"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category", default: "files", null: false
    t.boolean "customer_visible", default: true, null: false
    t.integer "position", default: 0, null: false
    t.boolean "cover", default: false, null: false
    t.boolean "hidden", default: false, null: false
    t.text "source_url"
    t.bigint "order_id"
    t.bigint "order_item_id"
    t.bigint "media_group_id"
    t.index ["listing_id", "category", "position"], name: "index_media_assets_on_listing_id_and_category_and_position"
    t.index ["listing_id", "category"], name: "index_media_assets_on_listing_id_and_category"
    t.index ["listing_id", "cover"], name: "index_media_assets_on_listing_id_and_cover"
    t.index ["listing_id"], name: "index_media_assets_on_listing_id"
    t.index ["media_group_id", "position"], name: "index_media_assets_on_media_group_id_and_position"
    t.index ["media_group_id"], name: "index_media_assets_on_media_group_id"
    t.index ["order_id", "order_item_id"], name: "index_media_assets_on_order_id_and_order_item_id"
    t.index ["order_id"], name: "index_media_assets_on_order_id"
    t.index ["order_item_id"], name: "index_media_assets_on_order_item_id"
    t.index ["organization_id", "status"], name: "index_media_assets_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_media_assets_on_organization_id"
    t.index ["source_url"], name: "index_media_assets_on_source_url"
    t.index ["storage_key"], name: "index_media_assets_on_storage_key", unique: true
    t.index ["uploaded_by_id"], name: "index_media_assets_on_uploaded_by_id"
  end

  create_table "media_groups", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "customer_visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["listing_id", "name"], name: "index_media_groups_on_listing_id_and_name", unique: true
    t.index ["listing_id", "position"], name: "index_media_groups_on_listing_id_and_position"
    t.index ["listing_id"], name: "index_media_groups_on_listing_id"
    t.index ["organization_id"], name: "index_media_groups_on_organization_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.string "visibility", default: "participants", null: false
    t.jsonb "attachments", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_messages_on_author_id"
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "notifiable_type", null: false
    t.bigint "notifiable_id", null: false
    t.string "kind", null: false
    t.string "recipient", null: false
    t.string "deduplication_key", null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.text "last_error"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deduplication_key"], name: "index_notification_deliveries_on_deduplication_key", unique: true
    t.index ["notifiable_type", "notifiable_id"], name: "index_notification_deliveries_on_notifiable"
    t.index ["organization_id"], name: "index_notification_deliveries_on_organization_id"
    t.index ["status", "created_at"], name: "index_notification_deliveries_on_status_and_created_at"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id"
    t.bigint "product_variant_id"
    t.string "title", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", null: false
    t.integer "total_cents", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "options", default: {}, null: false
    t.datetime "cancelled_at"
    t.index ["cancelled_at"], name: "index_order_items_on_cancelled_at"
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.index ["product_variant_id"], name: "index_order_items_on_product_variant_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "client_account_id", null: false
    t.bigint "listing_id"
    t.string "status", default: "draft", null: false
    t.string "payment_mode", default: "pay_later", null: false
    t.string "currency", default: "cad", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "discount_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.string "source", default: "crm", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "fulfillment_status", default: "unfulfilled", null: false
    t.string "tags", default: [], null: false, array: true
    t.string "discount_type", default: "fixed", null: false
    t.integer "discount_rate_basis_points", default: 0, null: false
    t.integer "fee_cents", default: 0, null: false
    t.string "fee_label", default: "Service fee", null: false
    t.index ["client_account_id"], name: "index_orders_on_client_account_id"
    t.index ["listing_id"], name: "index_orders_on_listing_id"
    t.index ["organization_id", "fulfillment_status"], name: "index_orders_on_organization_id_and_fulfillment_status"
    t.index ["organization_id", "status"], name: "index_orders_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_orders_on_organization_id"
    t.index ["tags"], name: "index_orders_on_tags", using: :gin
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "time_zone", default: "Pacific Time (US & Canada)", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.bigint "organization_id", null: false
    t.string "provider", null: false
    t.string "provider_payment_id"
    t.string "status", default: "pending", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "cad", null: false
    t.datetime "paid_at"
    t.jsonb "provider_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "status"], name: "index_payments_on_invoice_id_and_status"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["organization_id"], name: "index_payments_on_organization_id"
    t.index ["provider", "provider_payment_id"], name: "index_payments_on_provider_and_provider_payment_id", unique: true
  end

  create_table "payroll_items", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.bigint "order_id"
    t.bigint "order_item_id"
    t.bigint "team_member_id"
    t.bigint "created_by_id", null: false
    t.string "title", null: false
    t.text "notes"
    t.integer "amount_cents", null: false
    t.datetime "submitted_at"
    t.datetime "paid_at"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_payroll_items_on_created_by_id"
    t.index ["listing_id", "status"], name: "index_payroll_items_on_listing_id_and_status"
    t.index ["listing_id"], name: "index_payroll_items_on_listing_id"
    t.index ["order_id"], name: "index_payroll_items_on_order_id"
    t.index ["order_item_id"], name: "index_payroll_items_on_order_item_id"
    t.index ["organization_id", "status", "submitted_at"], name: "idx_on_organization_id_status_submitted_at_82b790176b"
    t.index ["organization_id"], name: "index_payroll_items_on_organization_id"
    t.index ["team_member_id"], name: "index_payroll_items_on_team_member_id"
  end

  create_table "product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "external_id"
    t.string "title", null: false
    t.integer "price_cents", null: false
    t.integer "duration_minutes"
    t.integer "sqft_min"
    t.integer "sqft_max"
    t.string "quantity_label"
    t.boolean "active", default: true, null: false
    t.jsonb "source_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "external_id"], name: "index_product_variants_on_product_id_and_external_id", unique: true
    t.index ["product_id"], name: "index_product_variants_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "external_source"
    t.string "external_id"
    t.string "slug", null: false
    t.string "title", null: false
    t.string "kind", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.boolean "bundle_candidate", default: false, null: false
    t.boolean "do_not_recommend", default: false, null: false
    t.jsonb "categories", default: [], null: false
    t.jsonb "capabilities", default: [], null: false
    t.jsonb "requires_capabilities", default: [], null: false
    t.jsonb "source_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "external_source", "external_id"], name: "index_products_on_org_and_external_identity", unique: true
    t.index ["organization_id", "slug"], name: "index_products_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_products_on_organization_id"
  end

  create_table "property_sites", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "custom_domain"
    t.datetime "published_at"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "customer_visible", default: true, null: false
    t.string "site_kind", default: "branded", null: false
    t.index ["listing_id"], name: "index_property_sites_on_listing_id"
    t.index ["organization_id", "slug"], name: "index_property_sites_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_property_sites_on_organization_id"
  end

  create_table "saved_listing_views", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "access", default: "personal", null: false
    t.jsonb "filters", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "position"], name: "index_saved_listing_views_on_organization_id_and_position"
    t.index ["organization_id", "user_id", "name"], name: "idx_on_organization_id_user_id_name_845fd7fd12", unique: true
    t.index ["organization_id"], name: "index_saved_listing_views_on_organization_id"
    t.index ["user_id"], name: "index_saved_listing_views_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "invitation_token"
    t.datetime "invitation_created_at"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.integer "invitation_limit"
    t.string "invited_by_type"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.bigint "organization_id"
    t.string "name", default: "", null: false
    t.string "role", default: "manager", null: false
    t.string "status", default: "active", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workflow_columns", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "color", default: "#171525", null: false
    t.string "category", default: "active", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "key"], name: "index_workflow_columns_on_organization_id_and_key", unique: true
    t.index ["organization_id", "position"], name: "index_workflow_columns_on_organization_id_and_position"
    t.index ["organization_id"], name: "index_workflow_columns_on_organization_id"
  end

  create_table "workflow_tasks", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "assignee_id"
    t.string "title", null: false
    t.string "status", default: "todo", null: false
    t.string "stage", default: "intake", null: false
    t.boolean "customer_visible", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "due_at"
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "priority", default: "normal", null: false
    t.index ["assignee_id"], name: "index_workflow_tasks_on_assignee_id"
    t.index ["listing_id"], name: "index_workflow_tasks_on_listing_id"
    t.index ["organization_id", "status", "position"], name: "idx_on_organization_id_status_position_3a4fef4137"
    t.index ["organization_id", "status", "stage"], name: "index_workflow_tasks_on_organization_id_and_status_and_stage"
    t.index ["organization_id"], name: "index_workflow_tasks_on_organization_id"
  end

  add_foreign_key "activity_events", "organizations"
  add_foreign_key "activity_events", "users", column: "actor_id"
  add_foreign_key "appointment_events", "appointments"
  add_foreign_key "appointment_events", "users", column: "actor_id"
  add_foreign_key "appointment_items", "appointments"
  add_foreign_key "appointment_items", "order_items"
  add_foreign_key "appointment_team_members", "appointments"
  add_foreign_key "appointment_team_members", "users"
  add_foreign_key "appointments", "listings"
  add_foreign_key "appointments", "orders"
  add_foreign_key "appointments", "organizations"
  add_foreign_key "appointments", "users", column: "assigned_user_id"
  add_foreign_key "catalog_sync_runs", "organizations"
  add_foreign_key "client_accounts", "organizations"
  add_foreign_key "client_memberships", "client_accounts"
  add_foreign_key "client_memberships", "users"
  add_foreign_key "conversation_memberships", "conversations"
  add_foreign_key "conversation_memberships", "users"
  add_foreign_key "conversations", "client_accounts"
  add_foreign_key "conversations", "listings"
  add_foreign_key "conversations", "organizations"
  add_foreign_key "invoices", "client_accounts"
  add_foreign_key "invoices", "listings"
  add_foreign_key "invoices", "orders"
  add_foreign_key "invoices", "organizations"
  add_foreign_key "listing_assignments", "listings"
  add_foreign_key "listing_assignments", "users"
  add_foreign_key "listing_custom_fields", "listings"
  add_foreign_key "listing_customers", "client_accounts"
  add_foreign_key "listing_customers", "listings"
  add_foreign_key "listing_feedbacks", "client_accounts"
  add_foreign_key "listing_feedbacks", "listings"
  add_foreign_key "listing_feedbacks", "orders"
  add_foreign_key "listing_feedbacks", "organizations"
  add_foreign_key "listing_notes", "listings"
  add_foreign_key "listing_notes", "organizations"
  add_foreign_key "listing_notes", "users", column: "author_id"
  add_foreign_key "listing_view_preferences", "users"
  add_foreign_key "listings", "client_accounts"
  add_foreign_key "listings", "organizations"
  add_foreign_key "marketing_materials", "listings"
  add_foreign_key "marketing_materials", "organizations"
  add_foreign_key "marketing_materials", "users", column: "created_by_id"
  add_foreign_key "media_assets", "listings"
  add_foreign_key "media_assets", "media_groups"
  add_foreign_key "media_assets", "order_items"
  add_foreign_key "media_assets", "orders"
  add_foreign_key "media_assets", "organizations"
  add_foreign_key "media_assets", "users", column: "uploaded_by_id"
  add_foreign_key "media_groups", "listings"
  add_foreign_key "media_groups", "organizations"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "author_id"
  add_foreign_key "notification_deliveries", "organizations"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_variants"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "client_accounts"
  add_foreign_key "orders", "listings"
  add_foreign_key "orders", "organizations"
  add_foreign_key "payments", "invoices"
  add_foreign_key "payments", "organizations"
  add_foreign_key "payroll_items", "listings"
  add_foreign_key "payroll_items", "order_items"
  add_foreign_key "payroll_items", "orders"
  add_foreign_key "payroll_items", "organizations"
  add_foreign_key "payroll_items", "users", column: "created_by_id"
  add_foreign_key "payroll_items", "users", column: "team_member_id"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "organizations"
  add_foreign_key "property_sites", "listings"
  add_foreign_key "property_sites", "organizations"
  add_foreign_key "saved_listing_views", "organizations"
  add_foreign_key "saved_listing_views", "users"
  add_foreign_key "users", "organizations"
  add_foreign_key "workflow_columns", "organizations"
  add_foreign_key "workflow_tasks", "listings"
  add_foreign_key "workflow_tasks", "organizations"
  add_foreign_key "workflow_tasks", "users", column: "assignee_id"
end
