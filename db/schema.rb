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

ActiveRecord::Schema[8.0].define(version: 2026_09_13_160000) do
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
    t.string "origin", default: "native", null: false
    t.index ["assigned_user_id"], name: "index_appointments_on_assigned_user_id"
    t.index ["listing_id"], name: "index_appointments_on_listing_id"
    t.index ["order_id"], name: "index_appointments_on_order_id"
    t.index ["organization_id", "request_status"], name: "index_appointments_on_organization_id_and_request_status"
    t.index ["organization_id", "starts_at"], name: "index_appointments_on_organization_id_and_starts_at"
    t.index ["organization_id"], name: "index_appointments_on_organization_id"
    t.index ["origin"], name: "index_appointments_on_origin"
    t.exclusion_constraint "organization_id WITH =, assigned_user_id WITH =, tsrange(starts_at, ends_at, '[)'::text) WITH &&", where: "(assigned_user_id IS NOT NULL) AND ((status)::text <> 'cancelled'::text)", using: :gist, name: "no_overlapping_staff_appointments"
  end

  create_table "board_attachments", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "board_id", null: false
    t.bigint "workflow_task_id", null: false
    t.bigint "task_comment_id"
    t.bigint "uploaded_by_id"
    t.string "status", default: "pending", null: false
    t.string "storage_key", null: false
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size", default: 0, null: false
    t.integer "width"
    t.integer "height"
    t.integer "duration_seconds"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "status"], name: "index_board_attachments_on_board_id_and_status"
    t.index ["board_id"], name: "index_board_attachments_on_board_id"
    t.index ["organization_id"], name: "index_board_attachments_on_organization_id"
    t.index ["storage_key"], name: "index_board_attachments_on_storage_key", unique: true
    t.index ["task_comment_id", "created_at"], name: "index_board_attachments_on_task_comment_id_and_created_at"
    t.index ["task_comment_id"], name: "index_board_attachments_on_task_comment_id"
    t.index ["uploaded_by_id"], name: "index_board_attachments_on_uploaded_by_id"
    t.index ["workflow_task_id", "created_at"], name: "index_board_attachments_on_workflow_task_id_and_created_at"
    t.index ["workflow_task_id"], name: "index_board_attachments_on_workflow_task_id"
  end

  create_table "board_labels", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.string "name", null: false
    t.string "color", default: "#e8f7ed", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "board_id, lower((name)::text)", name: "index_board_labels_on_board_id_and_lower_name", unique: true
    t.index ["board_id"], name: "index_board_labels_on_board_id"
  end

  create_table "board_memberships", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.string "member_type", null: false
    t.bigint "member_id", null: false
    t.string "access", default: "contributor", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "member_type", "member_id"], name: "index_board_memberships_on_board_and_member", unique: true
    t.index ["board_id"], name: "index_board_memberships_on_board_id"
    t.index ["member_type", "member_id"], name: "index_board_memberships_on_member_type_and_member_id"
  end

  create_table "board_workflow_actions", force: :cascade do |t|
    t.bigint "board_workflow_id", null: false
    t.string "action_type", null: false
    t.jsonb "configuration", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_workflow_id", "position"], name: "index_board_workflow_actions_on_board_workflow_id_and_position"
    t.index ["board_workflow_id"], name: "index_board_workflow_actions_on_board_workflow_id"
  end

  create_table "board_workflow_conditions", force: :cascade do |t|
    t.bigint "board_workflow_id", null: false
    t.string "field", null: false
    t.string "operator", null: false
    t.jsonb "value", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_workflow_id", "position"], name: "idx_on_board_workflow_id_position_cfc135b29c"
    t.index ["board_workflow_id"], name: "index_board_workflow_conditions_on_board_workflow_id"
  end

  create_table "board_workflow_run_steps", force: :cascade do |t|
    t.bigint "board_workflow_run_id", null: false
    t.bigint "board_workflow_action_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "input", default: {}, null: false
    t.jsonb "output", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_workflow_action_id"], name: "index_board_workflow_run_steps_on_board_workflow_action_id"
    t.index ["board_workflow_run_id", "position"], name: "index_workflow_run_steps_on_run_and_position"
    t.index ["board_workflow_run_id"], name: "index_board_workflow_run_steps_on_board_workflow_run_id"
  end

  create_table "board_workflow_runs", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "board_workflow_id", null: false
    t.bigint "order_id", null: false
    t.string "idempotency_key", null: false
    t.string "status", default: "pending", null: false
    t.datetime "triggered_at", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "retry_count", default: 0, null: false
    t.text "error"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_workflow_id"], name: "index_board_workflow_runs_on_board_workflow_id"
    t.index ["idempotency_key"], name: "index_board_workflow_runs_on_idempotency_key", unique: true
    t.index ["order_id"], name: "index_board_workflow_runs_on_order_id"
    t.index ["organization_id", "status", "created_at"], name: "idx_on_organization_id_status_created_at_6abfe0b3c1"
    t.index ["organization_id"], name: "index_board_workflow_runs_on_organization_id"
  end

  create_table "board_workflow_status_mappings", force: :cascade do |t|
    t.bigint "board_workflow_id", null: false
    t.string "source_status", null: false
    t.string "target_column_key", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_workflow_id", "source_status"], name: "index_workflow_status_mappings_on_workflow_and_source", unique: true
    t.index ["board_workflow_id"], name: "index_board_workflow_status_mappings_on_board_workflow_id"
  end

  create_table "board_workflows", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "board_id", null: false
    t.bigint "created_by_id"
    t.string "name", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "trigger_key", default: "order_approved", null: false
    t.boolean "is_default", default: false, null: false
    t.integer "workflow_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "name"], name: "index_board_workflows_on_board_id_and_name", unique: true
    t.index ["board_id"], name: "index_board_workflows_on_board_id"
    t.index ["created_by_id"], name: "index_board_workflows_on_created_by_id"
    t.index ["organization_id", "trigger_key", "enabled"], name: "idx_on_organization_id_trigger_key_enabled_b070f5cca6"
    t.index ["organization_id"], name: "index_board_workflows_on_organization_id"
  end

  create_table "boards", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "kind", default: "production", null: false
    t.string "visibility", default: "organization", null: false
    t.boolean "requires_listing", default: true, null: false
    t.boolean "client_visible", default: true, null: false
    t.boolean "archived", default: false, null: false
    t.integer "position", default: 0, null: false
    t.bigint "created_by_id"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_boards_on_created_by_id"
    t.index ["organization_id", "archived", "position"], name: "index_boards_on_organization_id_and_archived_and_position"
    t.index ["organization_id", "slug"], name: "index_boards_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_boards_on_organization_id"
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

  create_table "client_account_tags", force: :cascade do |t|
    t.bigint "client_account_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_account_id", "tag_id"], name: "index_client_account_tags_on_client_account_id_and_tag_id", unique: true
    t.index ["client_account_id"], name: "index_client_account_tags_on_client_account_id"
    t.index ["tag_id"], name: "index_client_account_tags_on_tag_id"
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
    t.string "origin", default: "native", null: false
    t.text "description"
    t.text "internal_note"
    t.string "logo_url"
    t.string "website"
    t.string "brokerage_website"
    t.string "affiliate_id"
    t.datetime "archived_at"
    t.boolean "lock_downloads_before_payment", default: false, null: false
    t.boolean "display_original_price", default: true, null: false
    t.boolean "suppress_payment_reminders", default: false, null: false
    t.bigint "billing_user_id"
    t.boolean "billing_pays_externally", default: false, null: false
    t.string "billing_visibility", default: "everyone", null: false
    t.string "pricing_visibility", default: "hidden", null: false
    t.string "downloads_visibility", default: "hidden", null: false
    t.string "marketing_templates_visibility", default: "hidden", null: false
    t.jsonb "notification_preferences", default: {}, null: false
    t.bigint "order_form_id"
    t.string "member_listing_access", default: "all_team_listings", null: false
    t.index "organization_id, lower((affiliate_id)::text)", name: "index_client_accounts_on_organization_and_affiliate", unique: true, where: "(affiliate_id IS NOT NULL)"
    t.index ["billing_user_id"], name: "index_client_accounts_on_billing_user_id"
    t.index ["order_form_id"], name: "index_client_accounts_on_order_form_id"
    t.index ["organization_id", "archived_at"], name: "index_client_accounts_on_organization_and_archived"
    t.index ["organization_id", "name"], name: "index_client_accounts_on_organization_id_and_name"
    t.index ["organization_id"], name: "index_client_accounts_on_organization_id"
    t.index ["origin"], name: "index_client_accounts_on_origin"
    t.check_constraint "billing_visibility::text = ANY (ARRAY['hidden'::character varying, 'admins'::character varying, 'everyone'::character varying]::text[])", name: "client_accounts_billing_visibility_values"
    t.check_constraint "downloads_visibility::text = ANY (ARRAY['hidden'::character varying, 'admins'::character varying, 'everyone'::character varying]::text[])", name: "client_accounts_downloads_visibility_values"
    t.check_constraint "marketing_templates_visibility::text = ANY (ARRAY['hidden'::character varying, 'admins'::character varying, 'everyone'::character varying]::text[])", name: "client_accounts_marketing_templates_visibility_values"
    t.check_constraint "member_listing_access::text = ANY (ARRAY['all_team_listings'::character varying, 'attached_listings'::character varying]::text[])", name: "client_accounts_member_listing_access_values"
    t.check_constraint "pricing_visibility::text = ANY (ARRAY['hidden'::character varying, 'admins'::character varying, 'everyone'::character varying]::text[])", name: "client_accounts_pricing_visibility_values"
  end

  create_table "client_memberships", force: :cascade do |t|
    t.bigint "client_account_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "invitation_accepted_at"
    t.boolean "is_default", default: false, null: false
    t.boolean "listing_delivery_notification_enabled", default: true, null: false
    t.index ["client_account_id", "user_id"], name: "index_client_memberships_on_client_and_user", unique: true
    t.index ["client_account_id"], name: "index_client_memberships_on_client_account_id"
    t.index ["user_id", "status"], name: "index_client_memberships_on_user_and_status"
    t.index ["user_id"], name: "index_client_memberships_on_user_id"
    t.index ["user_id"], name: "index_one_default_client_membership_per_user", unique: true, where: "is_default"
  end

  create_table "conversation_attachments", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.bigint "uploaded_by_id"
    t.string "status", default: "pending", null: false
    t.string "storage_key", null: false
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "idx_on_conversation_id_created_at_6f99b48142"
    t.index ["conversation_id"], name: "index_conversation_attachments_on_conversation_id"
    t.index ["message_id", "created_at"], name: "index_conversation_attachments_on_message_id_and_created_at"
    t.index ["message_id"], name: "index_conversation_attachments_on_message_id"
    t.index ["organization_id"], name: "index_conversation_attachments_on_organization_id"
    t.index ["storage_key"], name: "index_conversation_attachments_on_storage_key", unique: true
    t.index ["uploaded_by_id"], name: "index_conversation_attachments_on_uploaded_by_id"
  end

  create_table "conversation_memberships", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "participant", null: false
    t.datetime "last_read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position", default: 0, null: false
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
    t.string "retention_period", default: "two_months", null: false
    t.index ["client_account_id"], name: "index_conversations_on_client_account_id"
    t.index ["listing_id"], name: "index_conversations_on_listing_id"
    t.index ["organization_id", "client_account_id"], name: "index_one_client_conversation_per_account", unique: true, where: "(((kind)::text = 'client'::text) AND (client_account_id IS NOT NULL))"
    t.index ["organization_id", "kind", "last_message_at"], name: "idx_on_organization_id_kind_last_message_at_fcb0d57e64"
    t.index ["organization_id"], name: "index_conversations_on_organization_id"
    t.index ["retention_period"], name: "index_conversations_on_retention_period"
    t.check_constraint "retention_period::text = ANY (ARRAY['two_months'::character varying::text, 'six_months'::character varying::text, 'one_year'::character varying::text, 'forever'::character varying::text])", name: "conversations_retention_period_values"
  end

  create_table "coupons", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "code", null: false
    t.string "description"
    t.string "discount_type", default: "fixed", null: false
    t.integer "amount_cents", default: 0, null: false
    t.integer "rate_basis_points", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.integer "max_redemptions"
    t.integer "redemption_count", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_coupons_on_organization_id_and_code", unique: true
    t.index ["organization_id"], name: "index_coupons_on_organization_id"
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.bigint "actor_id"
    t.bigint "order_id"
    t.integer "amount_cents", null: false
    t.integer "balance_after_cents", null: false
    t.string "reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_credit_transactions_on_actor_id"
    t.index ["order_id"], name: "index_credit_transactions_on_order_id"
    t.index ["organization_id"], name: "index_credit_transactions_on_organization_id"
    t.index ["user_id", "created_at"], name: "index_credit_transactions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
    t.check_constraint "amount_cents <> 0", name: "credit_transactions_amount_not_zero"
    t.check_constraint "balance_after_cents >= 0", name: "credit_transactions_balance_not_negative"
  end

  create_table "customer_blocked_staff", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "staff_id"], name: "index_customer_blocked_staff_on_customer_id_and_staff_id", unique: true
    t.index ["customer_id"], name: "index_customer_blocked_staff_on_customer_id"
    t.index ["staff_id"], name: "index_customer_blocked_staff_on_staff_id"
  end

  create_table "external_records", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "integration_connection_id", null: false
    t.bigint "integration_import_run_id"
    t.string "provider", null: false
    t.string "resource_type", null: false
    t.string "external_id", null: false
    t.string "record_type"
    t.bigint "record_id"
    t.jsonb "source_payload", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "sync_status", default: "imported", null: false
    t.datetime "source_created_at"
    t.datetime "source_updated_at"
    t.datetime "last_imported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_connection_id", "resource_type", "external_id"], name: "index_external_records_on_connection_resource_external_id", unique: true
    t.index ["integration_connection_id"], name: "index_external_records_on_integration_connection_id"
    t.index ["integration_import_run_id"], name: "index_external_records_on_integration_import_run_id"
    t.index ["organization_id"], name: "index_external_records_on_organization_id"
    t.index ["record_type", "record_id"], name: "index_external_records_on_record"
  end

  create_table "integration_connections", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "provider", null: false
    t.text "api_key"
    t.string "status", default: "disconnected", null: false
    t.datetime "last_validated_at"
    t.datetime "last_imported_at"
    t.jsonb "endpoint_coverage", default: {}, null: false
    t.datetime "credentials_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "provider"], name: "index_integration_connections_on_organization_id_and_provider", unique: true
    t.index ["organization_id"], name: "index_integration_connections_on_organization_id"
  end

  create_table "integration_import_runs", force: :cascade do |t|
    t.bigint "integration_connection_id", null: false
    t.bigint "organization_id", null: false
    t.string "provider", null: false
    t.string "status", default: "pending", null: false
    t.string "phase"
    t.jsonb "counts", default: {}, null: false
    t.jsonb "coverage", default: {}, null: false
    t.jsonb "error_details", default: [], null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "requested_resources", default: [], null: false
    t.date "import_start_date"
    t.string "conflict_resolution", default: "skip", null: false
    t.date "import_end_date"
    t.datetime "heartbeat_at"
    t.string "error_code"
    t.index ["error_code"], name: "index_integration_import_runs_on_error_code"
    t.index ["integration_connection_id"], name: "index_integration_import_runs_on_integration_connection_id"
    t.index ["organization_id", "provider", "created_at"], name: "idx_on_organization_id_provider_created_at_7ddb91d344"
    t.index ["organization_id"], name: "index_integration_import_runs_on_organization_id"
    t.index ["status", "heartbeat_at"], name: "index_integration_import_runs_on_status_and_heartbeat_at"
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
    t.string "origin", default: "native", null: false
    t.index ["client_account_id"], name: "index_invoices_on_client_account_id"
    t.index ["listing_id"], name: "index_invoices_on_listing_id"
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["organization_id", "number"], name: "index_invoices_on_organization_id_and_number", unique: true
    t.index ["organization_id", "status"], name: "index_invoices_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_invoices_on_organization_id"
    t.index ["origin"], name: "index_invoices_on_origin"
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

  create_table "listing_memberships", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.bigint "client_membership_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_membership_id"], name: "index_listing_memberships_on_client_membership_id"
    t.index ["listing_id", "client_membership_id"], name: "idx_on_listing_id_client_membership_id_f240efd580", unique: true
    t.index ["listing_id"], name: "index_listing_memberships_on_listing_id"
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
    t.string "origin", default: "native", null: false
    t.string "property_status", default: "coming_soon", null: false
    t.string "property_type"
    t.integer "price_cents"
    t.decimal "lot_acres", precision: 8, scale: 3
    t.string "parking"
    t.integer "year_built"
    t.date "mls_live_date"
    t.bigint "booked_by_id"
    t.index ["booked_by_id"], name: "index_listings_on_booked_by_id"
    t.index ["client_account_id"], name: "index_listings_on_client_account_id"
    t.index ["customer_first_viewed_at"], name: "index_listings_on_customer_first_viewed_at"
    t.index ["organization_id", "delivery_status"], name: "index_listings_on_organization_id_and_delivery_status"
    t.index ["organization_id", "property_status"], name: "index_listings_on_organization_id_and_property_status"
    t.index ["organization_id", "public_slug"], name: "index_listings_on_organization_id_and_public_slug", unique: true
    t.index ["organization_id", "status"], name: "index_listings_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_listings_on_organization_id"
    t.index ["origin"], name: "index_listings_on_origin"
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
    t.string "origin", default: "native", null: false
    t.bigint "order_deliverable_id"
    t.integer "version", default: 1, null: false
    t.bigint "superseded_by_id"
    t.index ["listing_id", "category", "position"], name: "index_media_assets_on_listing_id_and_category_and_position"
    t.index ["listing_id", "category"], name: "index_media_assets_on_listing_id_and_category"
    t.index ["listing_id", "cover"], name: "index_media_assets_on_listing_id_and_cover"
    t.index ["listing_id"], name: "index_media_assets_on_listing_id"
    t.index ["media_group_id", "position"], name: "index_media_assets_on_media_group_id_and_position"
    t.index ["media_group_id"], name: "index_media_assets_on_media_group_id"
    t.index ["order_deliverable_id", "version"], name: "index_media_assets_on_order_deliverable_id_and_version"
    t.index ["order_deliverable_id"], name: "index_media_assets_on_order_deliverable_id"
    t.index ["order_id", "order_item_id"], name: "index_media_assets_on_order_id_and_order_item_id"
    t.index ["order_id"], name: "index_media_assets_on_order_id"
    t.index ["order_item_id"], name: "index_media_assets_on_order_item_id"
    t.index ["organization_id", "status"], name: "index_media_assets_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_media_assets_on_organization_id"
    t.index ["origin"], name: "index_media_assets_on_origin"
    t.index ["source_url"], name: "index_media_assets_on_source_url"
    t.index ["storage_key"], name: "index_media_assets_on_storage_key", unique: true
    t.index ["superseded_by_id"], name: "index_media_assets_on_superseded_by_id"
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

  create_table "media_review_assets", force: :cascade do |t|
    t.bigint "media_review_id", null: false
    t.bigint "media_asset_id", null: false
    t.bigint "order_deliverable_id"
    t.integer "asset_version", default: 1, null: false
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["media_asset_id"], name: "index_media_review_assets_on_media_asset_id"
    t.index ["media_review_id", "media_asset_id"], name: "index_media_review_assets_on_review_and_asset", unique: true
    t.index ["media_review_id", "order_deliverable_id", "position"], name: "index_media_review_assets_on_review_deliverable_position"
    t.index ["media_review_id"], name: "index_media_review_assets_on_media_review_id"
    t.index ["order_deliverable_id"], name: "index_media_review_assets_on_order_deliverable_id"
  end

  create_table "media_review_comments", force: :cascade do |t|
    t.bigint "media_review_thread_id", null: false
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.text "body_html"
    t.string "status", default: "draft", null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_media_review_comments_on_author_id"
    t.index ["media_review_thread_id", "created_at"], name: "index_media_review_comments_on_thread_and_created_at"
    t.index ["media_review_thread_id"], name: "index_media_review_comments_on_media_review_thread_id"
  end

  create_table "media_review_deliverables", force: :cascade do |t|
    t.bigint "media_review_id", null: false
    t.bigint "order_deliverable_id", null: false
    t.integer "delivery_version", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["media_review_id", "order_deliverable_id"], name: "index_media_review_deliverables_on_review_and_deliverable", unique: true
    t.index ["media_review_id"], name: "index_media_review_deliverables_on_media_review_id"
    t.index ["order_deliverable_id"], name: "index_media_review_deliverables_on_order_deliverable_id"
  end

  create_table "media_review_threads", force: :cascade do |t|
    t.bigint "media_review_id", null: false
    t.bigint "media_review_asset_id"
    t.bigint "order_deliverable_id"
    t.bigint "created_by_id", null: false
    t.bigint "resolved_by_id"
    t.string "status", default: "open", null: false
    t.string "anchor_type", default: "asset", null: false
    t.integer "page_number"
    t.integer "time_start_ms"
    t.integer "time_end_ms"
    t.decimal "anchor_x", precision: 8, scale: 4
    t.decimal "anchor_y", precision: 8, scale: 4
    t.decimal "anchor_width", precision: 8, scale: 4
    t.decimal "anchor_height", precision: 8, scale: 4
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_media_review_threads_on_created_by_id"
    t.index ["media_review_asset_id"], name: "index_media_review_threads_on_media_review_asset_id"
    t.index ["media_review_id", "status"], name: "index_media_review_threads_on_review_and_status"
    t.index ["media_review_id"], name: "index_media_review_threads_on_media_review_id"
    t.index ["order_deliverable_id"], name: "index_media_review_threads_on_order_deliverable_id"
    t.index ["resolved_by_id"], name: "index_media_review_threads_on_resolved_by_id"
  end

  create_table "media_reviews", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id", null: false
    t.bigint "client_account_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "submitted_by_id"
    t.integer "number", null: false
    t.integer "delivery_version", default: 0, null: false
    t.string "status", default: "open", null: false
    t.string "outcome"
    t.text "summary"
    t.text "summary_html"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_account_id"], name: "index_media_reviews_on_client_account_id"
    t.index ["created_by_id"], name: "index_media_reviews_on_created_by_id"
    t.index ["listing_id", "client_account_id", "delivery_version"], name: "index_media_reviews_on_listing_account_version"
    t.index ["listing_id", "client_account_id", "number"], name: "index_media_reviews_on_listing_account_number", unique: true
    t.index ["listing_id", "client_account_id"], name: "index_media_reviews_one_open_per_listing_account", unique: true, where: "((status)::text = 'open'::text)"
    t.index ["listing_id"], name: "index_media_reviews_on_listing_id"
    t.index ["organization_id", "listing_id", "client_account_id"], name: "index_media_reviews_on_organization_listing_account"
    t.index ["organization_id"], name: "index_media_reviews_on_organization_id"
    t.index ["submitted_by_id"], name: "index_media_reviews_on_submitted_by_id"
  end

  create_table "message_media_references", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "media_asset_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["media_asset_id"], name: "index_message_media_references_on_media_asset_id"
    t.index ["message_id", "media_asset_id"], name: "index_message_media_references_on_message_and_asset", unique: true
    t.index ["message_id"], name: "index_message_media_references_on_message_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.string "visibility", default: "participants", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body_html"
    t.string "message_kind", default: "message", null: false
    t.bigint "listing_id"
    t.bigint "order_deliverable_id"
    t.bigint "media_review_id"
    t.index ["author_id"], name: "index_messages_on_author_id"
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id", "message_kind", "created_at"], name: "index_messages_on_conversation_kind_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["listing_id"], name: "index_messages_on_listing_id"
    t.index ["media_review_id"], name: "index_messages_on_media_review_id"
    t.index ["order_deliverable_id"], name: "index_messages_on_order_deliverable_id"
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
    t.string "channel", default: "email", null: false
    t.index ["deduplication_key"], name: "index_notification_deliveries_on_deduplication_key", unique: true
    t.index ["notifiable_type", "notifiable_id"], name: "index_notification_deliveries_on_notifiable"
    t.index ["organization_id"], name: "index_notification_deliveries_on_organization_id"
    t.index ["status", "created_at"], name: "index_notification_deliveries_on_status_and_created_at"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying::text, 'sms'::character varying::text, 'push'::character varying::text])", name: "notification_deliveries_channel_values"
  end

  create_table "order_deliverables", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "listing_id"
    t.bigint "order_id", null: false
    t.bigint "order_item_id", null: false
    t.bigint "product_component_id"
    t.bigint "service_product_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "deliverable_type", null: false
    t.integer "sla_days", default: 0, null: false
    t.integer "scope_sqft_min"
    t.integer "scope_sqft_max"
    t.string "scope_label"
    t.string "status", default: "not_started", null: false
    t.date "target_on"
    t.datetime "delivered_at"
    t.integer "delivery_version", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "cancelled_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "materialization_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["listing_id", "status"], name: "index_order_deliverables_on_listing_id_and_status"
    t.index ["listing_id"], name: "index_order_deliverables_on_listing_id"
    t.index ["materialization_key"], name: "index_order_deliverables_on_materialization_key", unique: true
    t.index ["order_id", "position"], name: "index_order_deliverables_on_order_id_and_position"
    t.index ["order_id"], name: "index_order_deliverables_on_order_id"
    t.index ["order_item_id"], name: "index_order_deliverables_on_order_item_id"
    t.index ["organization_id", "status"], name: "index_order_deliverables_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_order_deliverables_on_organization_id"
    t.index ["product_component_id"], name: "index_order_deliverables_on_product_component_id"
    t.index ["service_product_id"], name: "index_order_deliverables_on_service_product_id"
  end

  create_table "order_form_products", force: :cascade do |t|
    t.bigint "order_form_id", null: false
    t.bigint "product_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_form_id", "product_id"], name: "index_order_form_products_on_order_form_id_and_product_id", unique: true
    t.index ["order_form_id"], name: "index_order_form_products_on_order_form_id"
    t.index ["product_id"], name: "index_order_form_products_on_product_id"
  end

  create_table "order_forms", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_order_forms_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_order_forms_on_organization_id"
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
    t.string "origin", default: "native", null: false
    t.datetime "approved_at"
    t.integer "credit_applied_cents", default: 0, null: false
    t.bigint "ordered_by_id"
    t.index ["approved_at"], name: "index_orders_on_approved_at"
    t.index ["client_account_id"], name: "index_orders_on_client_account_id"
    t.index ["listing_id"], name: "index_orders_on_listing_id"
    t.index ["ordered_by_id"], name: "index_orders_on_ordered_by_id"
    t.index ["organization_id", "fulfillment_status"], name: "index_orders_on_organization_id_and_fulfillment_status"
    t.index ["organization_id", "status"], name: "index_orders_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_orders_on_organization_id"
    t.index ["origin"], name: "index_orders_on_origin"
    t.index ["tags"], name: "index_orders_on_tags", using: :gin
    t.check_constraint "credit_applied_cents >= 0", name: "orders_credit_applied_not_negative"
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

  create_table "payment_webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.bigint "payment_id"
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_payment_webhook_events_on_payment_id"
    t.index ["provider", "event_id"], name: "index_payment_webhook_events_on_provider_and_event_id", unique: true
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
    t.string "origin", default: "native", null: false
    t.index ["invoice_id", "status"], name: "index_payments_on_invoice_id_and_status"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["organization_id"], name: "index_payments_on_organization_id"
    t.index ["origin"], name: "index_payments_on_origin"
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

  create_table "pricing_plan_prices", force: :cascade do |t|
    t.bigint "pricing_plan_id", null: false
    t.bigint "product_variant_id", null: false
    t.integer "price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pricing_plan_id", "product_variant_id"], name: "idx_on_pricing_plan_id_product_variant_id_1375d84476", unique: true
    t.index ["pricing_plan_id"], name: "index_pricing_plan_prices_on_pricing_plan_id"
    t.index ["product_variant_id"], name: "index_pricing_plan_prices_on_product_variant_id"
  end

  create_table "pricing_plans", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.bigint "client_account_id"
    t.bigint "coupon_id"
    t.integer "priority", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["client_account_id", "active"], name: "index_pricing_plans_on_client_account_id_and_active"
    t.index ["client_account_id"], name: "index_pricing_plans_on_client_account_id"
    t.index ["coupon_id"], name: "index_pricing_plans_on_coupon_id"
    t.index ["organization_id", "active"], name: "index_pricing_plans_on_organization_id_and_active"
    t.index ["organization_id"], name: "index_pricing_plans_on_organization_id"
    t.index ["user_id", "active"], name: "index_pricing_plans_on_user_and_active"
    t.check_constraint "((client_account_id IS NOT NULL)::integer + (user_id IS NOT NULL)::integer) = 1", name: "pricing_plans_exactly_one_owner"
  end

  create_table "product_components", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "package_product_id", null: false
    t.bigint "service_product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_product_components_on_organization_id"
    t.index ["package_product_id", "position"], name: "index_product_components_on_package_position"
    t.index ["package_product_id", "service_product_id"], name: "index_product_components_on_package_and_service", unique: true
    t.index ["package_product_id"], name: "index_product_components_on_package_product_id"
    t.index ["service_product_id"], name: "index_product_components_on_service_product_id"
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
    t.string "origin", default: "native", null: false
    t.string "deliverable_type", default: "other", null: false
    t.integer "sla_days", default: 0, null: false
    t.index ["deliverable_type"], name: "index_products_on_deliverable_type"
    t.index ["organization_id", "external_source", "external_id"], name: "index_products_on_org_and_external_identity", unique: true
    t.index ["organization_id", "slug"], name: "index_products_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_products_on_organization_id"
    t.index ["origin"], name: "index_products_on_origin"
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
    t.string "origin", default: "native", null: false
    t.index ["listing_id"], name: "index_property_sites_on_listing_id"
    t.index ["organization_id", "slug"], name: "index_property_sites_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_property_sites_on_organization_id"
    t.index ["origin"], name: "index_property_sites_on_origin"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "user_agent"
    t.datetime "last_delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
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

  create_table "tags", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "color", default: "#6b7280", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "organization_id, lower((name)::text)", name: "index_tags_on_organization_and_lower_name", unique: true
    t.index ["organization_id"], name: "index_tags_on_organization_id"
    t.check_constraint "color::text ~ '^#[0-9a-fA-F]{6}$'::text", name: "tags_color_is_hex"
  end

  create_table "task_checklist_items", force: :cascade do |t|
    t.bigint "workflow_task_id", null: false
    t.bigint "completed_by_id"
    t.string "title", null: false
    t.integer "position", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_by_id"], name: "index_task_checklist_items_on_completed_by_id"
    t.index ["workflow_task_id", "position"], name: "index_task_checklist_items_on_workflow_task_id_and_position"
    t.index ["workflow_task_id"], name: "index_task_checklist_items_on_workflow_task_id"
  end

  create_table "task_comments", force: :cascade do |t|
    t.bigint "workflow_task_id", null: false
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body_html"
    t.bigint "parent_comment_id"
    t.index ["author_id"], name: "index_task_comments_on_author_id"
    t.index ["parent_comment_id", "created_at"], name: "index_task_comments_on_parent_comment_id_and_created_at"
    t.index ["parent_comment_id"], name: "index_task_comments_on_parent_comment_id"
    t.index ["workflow_task_id", "created_at"], name: "index_task_comments_on_workflow_task_id_and_created_at"
    t.index ["workflow_task_id"], name: "index_task_comments_on_workflow_task_id"
  end

  create_table "taxes", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.integer "rate_basis_points", default: 0, null: false
    t.string "scope", default: "custom", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "organization_id, lower((name)::text)", name: "index_taxes_on_organization_and_lower_name", unique: true
    t.index ["organization_id", "active"], name: "index_taxes_on_organization_id_and_active"
    t.index ["organization_id"], name: "index_taxes_on_organization_id"
  end

  create_table "travel_fees", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "fee_type", default: "flat", null: false
    t.integer "amount_cents", default: 0, null: false
    t.integer "rate_basis_points", default: 0, null: false
    t.integer "free_within_km"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "active"], name: "index_travel_fees_on_organization_id_and_active"
    t.index ["organization_id"], name: "index_travel_fees_on_organization_id"
  end

  create_table "user_group_memberships", force: :cascade do |t|
    t.bigint "user_group_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_group_id", "user_id"], name: "index_user_group_memberships_on_user_group_id_and_user_id", unique: true
    t.index ["user_group_id"], name: "index_user_group_memberships_on_user_group_id"
    t.index ["user_id"], name: "index_user_group_memberships_on_user_id"
  end

  create_table "user_groups", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "slug"], name: "index_user_groups_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_user_groups_on_organization_id"
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
    t.string "origin", default: "native", null: false
    t.string "phone"
    t.string "license_number"
    t.string "avatar_url"
    t.string "timezone"
    t.text "internal_note"
    t.jsonb "social_profiles", default: {}, null: false
    t.boolean "blocked_from_ordering", default: false, null: false
    t.integer "credit_balance_cents", default: 0, null: false
    t.jsonb "billing_address", default: {}, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["origin"], name: "index_users_on_origin"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.check_constraint "credit_balance_cents >= 0", name: "users_credit_balance_not_negative"
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
    t.bigint "board_id", null: false
    t.index ["board_id", "key"], name: "index_workflow_columns_on_board_id_and_key", unique: true
    t.index ["board_id", "position"], name: "index_workflow_columns_on_board_id_and_position"
    t.index ["board_id"], name: "index_workflow_columns_on_board_id"
    t.index ["organization_id", "position"], name: "index_workflow_columns_on_organization_id_and_position"
    t.index ["organization_id"], name: "index_workflow_columns_on_organization_id"
  end

  create_table "workflow_task_deliverables", force: :cascade do |t|
    t.bigint "workflow_task_id", null: false
    t.bigint "order_deliverable_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_deliverable_id"], name: "index_workflow_task_deliverables_on_order_deliverable_id"
    t.index ["workflow_task_id", "order_deliverable_id"], name: "index_task_deliverables_on_task_and_deliverable", unique: true
    t.index ["workflow_task_id"], name: "index_workflow_task_deliverables_on_workflow_task_id"
  end

  create_table "workflow_task_labels", force: :cascade do |t|
    t.bigint "workflow_task_id", null: false
    t.bigint "board_label_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_label_id"], name: "index_workflow_task_labels_on_board_label_id"
    t.index ["workflow_task_id", "board_label_id"], name: "index_workflow_task_labels_on_task_and_label", unique: true
    t.index ["workflow_task_id"], name: "index_workflow_task_labels_on_workflow_task_id"
  end

  create_table "workflow_task_placements", force: :cascade do |t|
    t.bigint "workflow_task_id", null: false
    t.bigint "board_id", null: false
    t.bigint "workflow_column_id", null: false
    t.integer "position", default: 0, null: false
    t.boolean "is_home", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "workflow_column_id", "position"], name: "index_task_placements_on_board_column_position"
    t.index ["board_id"], name: "index_workflow_task_placements_on_board_id"
    t.index ["workflow_column_id"], name: "index_workflow_task_placements_on_workflow_column_id"
    t.index ["workflow_task_id", "board_id"], name: "index_task_placements_on_task_and_board", unique: true
    t.index ["workflow_task_id"], name: "index_one_home_placement_per_task", unique: true, where: "is_home"
    t.index ["workflow_task_id"], name: "index_workflow_task_placements_on_workflow_task_id"
  end

  create_table "workflow_tasks", force: :cascade do |t|
    t.bigint "listing_id"
    t.bigint "organization_id", null: false
    t.bigint "assignee_id"
    t.string "title", null: false
    t.string "status", default: "todo", null: false
    t.boolean "customer_visible", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "due_at"
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "priority", default: "normal", null: false
    t.string "origin", default: "native", null: false
    t.bigint "board_id", null: false
    t.bigint "reporter_id"
    t.datetime "started_at"
    t.text "description_html"
    t.bigint "parent_task_id"
    t.string "task_kind", default: "task", null: false
    t.string "workflow_group_key"
    t.index ["assignee_id"], name: "index_workflow_tasks_on_assignee_id"
    t.index ["board_id", "status", "position"], name: "index_workflow_tasks_on_board_id_and_status_and_position"
    t.index ["board_id"], name: "index_workflow_tasks_on_board_id"
    t.index ["listing_id"], name: "index_workflow_tasks_on_listing_id"
    t.index ["organization_id", "status", "position"], name: "idx_on_organization_id_status_position_3a4fef4137"
    t.index ["organization_id", "workflow_group_key"], name: "index_workflow_tasks_on_organization_id_and_workflow_group_key"
    t.index ["organization_id"], name: "index_workflow_tasks_on_organization_id"
    t.index ["origin"], name: "index_workflow_tasks_on_origin"
    t.index ["parent_task_id"], name: "index_workflow_tasks_on_parent_task_id"
    t.index ["reporter_id"], name: "index_workflow_tasks_on_reporter_id"
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
  add_foreign_key "board_attachments", "boards"
  add_foreign_key "board_attachments", "organizations"
  add_foreign_key "board_attachments", "task_comments"
  add_foreign_key "board_attachments", "users", column: "uploaded_by_id"
  add_foreign_key "board_attachments", "workflow_tasks"
  add_foreign_key "board_labels", "boards"
  add_foreign_key "board_memberships", "boards"
  add_foreign_key "board_workflow_actions", "board_workflows"
  add_foreign_key "board_workflow_conditions", "board_workflows"
  add_foreign_key "board_workflow_run_steps", "board_workflow_actions"
  add_foreign_key "board_workflow_run_steps", "board_workflow_runs"
  add_foreign_key "board_workflow_runs", "board_workflows"
  add_foreign_key "board_workflow_runs", "orders"
  add_foreign_key "board_workflow_runs", "organizations"
  add_foreign_key "board_workflow_status_mappings", "board_workflows"
  add_foreign_key "board_workflows", "boards"
  add_foreign_key "board_workflows", "organizations"
  add_foreign_key "board_workflows", "users", column: "created_by_id"
  add_foreign_key "boards", "organizations"
  add_foreign_key "boards", "users", column: "created_by_id"
  add_foreign_key "catalog_sync_runs", "organizations"
  add_foreign_key "client_account_tags", "client_accounts", on_delete: :cascade
  add_foreign_key "client_account_tags", "tags", on_delete: :cascade
  add_foreign_key "client_accounts", "order_forms", on_delete: :nullify
  add_foreign_key "client_accounts", "organizations"
  add_foreign_key "client_accounts", "users", column: "billing_user_id", on_delete: :nullify
  add_foreign_key "client_memberships", "client_accounts"
  add_foreign_key "client_memberships", "users"
  add_foreign_key "conversation_attachments", "conversations"
  add_foreign_key "conversation_attachments", "messages"
  add_foreign_key "conversation_attachments", "organizations"
  add_foreign_key "conversation_attachments", "users", column: "uploaded_by_id"
  add_foreign_key "conversation_memberships", "conversations"
  add_foreign_key "conversation_memberships", "users"
  add_foreign_key "conversations", "client_accounts"
  add_foreign_key "conversations", "listings"
  add_foreign_key "conversations", "organizations"
  add_foreign_key "coupons", "organizations"
  add_foreign_key "credit_transactions", "orders", on_delete: :nullify
  add_foreign_key "credit_transactions", "organizations"
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "credit_transactions", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "customer_blocked_staff", "users", column: "customer_id", on_delete: :cascade
  add_foreign_key "customer_blocked_staff", "users", column: "staff_id", on_delete: :cascade
  add_foreign_key "external_records", "integration_connections"
  add_foreign_key "external_records", "integration_import_runs"
  add_foreign_key "external_records", "organizations"
  add_foreign_key "integration_connections", "organizations"
  add_foreign_key "integration_import_runs", "integration_connections"
  add_foreign_key "integration_import_runs", "organizations"
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
  add_foreign_key "listing_memberships", "client_memberships", on_delete: :cascade
  add_foreign_key "listing_memberships", "listings", on_delete: :cascade
  add_foreign_key "listing_notes", "listings"
  add_foreign_key "listing_notes", "organizations"
  add_foreign_key "listing_notes", "users", column: "author_id"
  add_foreign_key "listing_view_preferences", "users"
  add_foreign_key "listings", "client_accounts"
  add_foreign_key "listings", "organizations"
  add_foreign_key "listings", "users", column: "booked_by_id", on_delete: :nullify
  add_foreign_key "marketing_materials", "listings"
  add_foreign_key "marketing_materials", "organizations"
  add_foreign_key "marketing_materials", "users", column: "created_by_id"
  add_foreign_key "media_assets", "listings"
  add_foreign_key "media_assets", "media_assets", column: "superseded_by_id"
  add_foreign_key "media_assets", "media_groups"
  add_foreign_key "media_assets", "order_deliverables"
  add_foreign_key "media_assets", "order_items"
  add_foreign_key "media_assets", "orders"
  add_foreign_key "media_assets", "organizations"
  add_foreign_key "media_assets", "users", column: "uploaded_by_id"
  add_foreign_key "media_groups", "listings"
  add_foreign_key "media_groups", "organizations"
  add_foreign_key "media_review_assets", "media_assets"
  add_foreign_key "media_review_assets", "media_reviews"
  add_foreign_key "media_review_assets", "order_deliverables"
  add_foreign_key "media_review_comments", "media_review_threads"
  add_foreign_key "media_review_comments", "users", column: "author_id"
  add_foreign_key "media_review_deliverables", "media_reviews"
  add_foreign_key "media_review_deliverables", "order_deliverables"
  add_foreign_key "media_review_threads", "media_review_assets"
  add_foreign_key "media_review_threads", "media_reviews"
  add_foreign_key "media_review_threads", "order_deliverables"
  add_foreign_key "media_review_threads", "users", column: "created_by_id"
  add_foreign_key "media_review_threads", "users", column: "resolved_by_id"
  add_foreign_key "media_reviews", "client_accounts"
  add_foreign_key "media_reviews", "listings"
  add_foreign_key "media_reviews", "organizations"
  add_foreign_key "media_reviews", "users", column: "created_by_id"
  add_foreign_key "media_reviews", "users", column: "submitted_by_id"
  add_foreign_key "message_media_references", "media_assets"
  add_foreign_key "message_media_references", "messages"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "listings"
  add_foreign_key "messages", "media_reviews"
  add_foreign_key "messages", "order_deliverables"
  add_foreign_key "messages", "users", column: "author_id"
  add_foreign_key "notification_deliveries", "organizations"
  add_foreign_key "order_deliverables", "listings"
  add_foreign_key "order_deliverables", "order_items"
  add_foreign_key "order_deliverables", "orders"
  add_foreign_key "order_deliverables", "organizations"
  add_foreign_key "order_deliverables", "product_components"
  add_foreign_key "order_deliverables", "products", column: "service_product_id"
  add_foreign_key "order_form_products", "order_forms", on_delete: :cascade
  add_foreign_key "order_form_products", "products", on_delete: :cascade
  add_foreign_key "order_forms", "organizations"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_variants"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "client_accounts"
  add_foreign_key "orders", "listings"
  add_foreign_key "orders", "organizations"
  add_foreign_key "orders", "users", column: "ordered_by_id", on_delete: :nullify
  add_foreign_key "payment_webhook_events", "payments"
  add_foreign_key "payments", "invoices"
  add_foreign_key "payments", "organizations"
  add_foreign_key "payroll_items", "listings"
  add_foreign_key "payroll_items", "order_items"
  add_foreign_key "payroll_items", "orders"
  add_foreign_key "payroll_items", "organizations"
  add_foreign_key "payroll_items", "users", column: "created_by_id"
  add_foreign_key "payroll_items", "users", column: "team_member_id"
  add_foreign_key "pricing_plan_prices", "pricing_plans"
  add_foreign_key "pricing_plan_prices", "product_variants"
  add_foreign_key "pricing_plans", "client_accounts"
  add_foreign_key "pricing_plans", "coupons"
  add_foreign_key "pricing_plans", "organizations"
  add_foreign_key "pricing_plans", "users"
  add_foreign_key "product_components", "organizations"
  add_foreign_key "product_components", "products", column: "package_product_id"
  add_foreign_key "product_components", "products", column: "service_product_id"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "organizations"
  add_foreign_key "property_sites", "listings"
  add_foreign_key "property_sites", "organizations"
  add_foreign_key "push_subscriptions", "users", on_delete: :cascade
  add_foreign_key "saved_listing_views", "organizations"
  add_foreign_key "saved_listing_views", "users"
  add_foreign_key "tags", "organizations"
  add_foreign_key "task_checklist_items", "users", column: "completed_by_id"
  add_foreign_key "task_checklist_items", "workflow_tasks"
  add_foreign_key "task_comments", "task_comments", column: "parent_comment_id"
  add_foreign_key "task_comments", "users", column: "author_id"
  add_foreign_key "task_comments", "workflow_tasks"
  add_foreign_key "taxes", "organizations"
  add_foreign_key "travel_fees", "organizations"
  add_foreign_key "user_group_memberships", "user_groups"
  add_foreign_key "user_group_memberships", "users"
  add_foreign_key "user_groups", "organizations"
  add_foreign_key "users", "organizations"
  add_foreign_key "workflow_columns", "boards"
  add_foreign_key "workflow_columns", "organizations"
  add_foreign_key "workflow_task_deliverables", "order_deliverables"
  add_foreign_key "workflow_task_deliverables", "workflow_tasks"
  add_foreign_key "workflow_task_labels", "board_labels"
  add_foreign_key "workflow_task_labels", "workflow_tasks"
  add_foreign_key "workflow_task_placements", "boards"
  add_foreign_key "workflow_task_placements", "workflow_columns"
  add_foreign_key "workflow_task_placements", "workflow_tasks"
  add_foreign_key "workflow_tasks", "boards"
  add_foreign_key "workflow_tasks", "listings"
  add_foreign_key "workflow_tasks", "organizations"
  add_foreign_key "workflow_tasks", "users", column: "assignee_id"
  add_foreign_key "workflow_tasks", "users", column: "reporter_id"
  add_foreign_key "workflow_tasks", "workflow_tasks", column: "parent_task_id"
end
