class AddOneOpenMediaReviewIndex < ActiveRecord::Migration[8.0]
  def change
    # One draft per listing and customer account. A double click or a second
    # tab has to resume the draft rather than race to open another one.
    add_index :media_reviews, [ :listing_id, :client_account_id ], unique: true, where: "status = 'open'",
      name: "index_media_reviews_one_open_per_listing_account"
  end
end
