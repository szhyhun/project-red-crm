class CreateMediaReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :media_reviews do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :submitted_by, foreign_key: { to_table: :users }
      t.integer :number, null: false
      t.integer :delivery_version, null: false, default: 0
      t.string :status, null: false, default: "open"
      t.string :outcome
      t.text :summary
      t.text :summary_html
      t.datetime :submitted_at
      t.timestamps
    end
    add_index :media_reviews, [ :listing_id, :client_account_id, :number ], unique: true,
      name: "index_media_reviews_on_listing_account_number"
    add_index :media_reviews, [ :organization_id, :listing_id, :client_account_id ],
      name: "index_media_reviews_on_organization_listing_account"
    add_index :media_reviews, [ :listing_id, :client_account_id, :delivery_version ],
      name: "index_media_reviews_on_listing_account_version"

    create_table :media_review_deliverables do |t|
      t.references :media_review, null: false, foreign_key: true
      t.references :order_deliverable, null: false, foreign_key: true
      t.integer :delivery_version, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :media_review_deliverables, [ :media_review_id, :order_deliverable_id ], unique: true,
      name: "index_media_review_deliverables_on_review_and_deliverable"

    create_table :media_review_assets do |t|
      t.references :media_review, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: true
      t.references :order_deliverable, foreign_key: true
      t.integer :asset_version, null: false, default: 1
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :media_review_assets, [ :media_review_id, :media_asset_id ], unique: true,
      name: "index_media_review_assets_on_review_and_asset"
    add_index :media_review_assets, [ :media_review_id, :order_deliverable_id, :position ],
      name: "index_media_review_assets_on_review_deliverable_position"

    create_table :media_review_threads do |t|
      t.references :media_review, null: false, foreign_key: true
      t.references :media_review_asset, foreign_key: true
      t.references :order_deliverable, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "open"
      t.string :anchor_type, null: false, default: "asset"
      t.integer :page_number
      t.integer :time_start_ms
      t.integer :time_end_ms
      t.decimal :anchor_x, precision: 8, scale: 4
      t.decimal :anchor_y, precision: 8, scale: 4
      t.decimal :anchor_width, precision: 8, scale: 4
      t.decimal :anchor_height, precision: 8, scale: 4
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :media_review_threads, [ :media_review_id, :status ],
      name: "index_media_review_threads_on_review_and_status"

    create_table :media_review_comments do |t|
      t.references :media_review_thread, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.text :body_html
      t.string :status, null: false, default: "draft"
      t.datetime :edited_at
      t.timestamps
    end
    add_index :media_review_comments, [ :media_review_thread_id, :created_at ],
      name: "index_media_review_comments_on_thread_and_created_at"

    add_reference :messages, :media_review, foreign_key: true
  end
end
