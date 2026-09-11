class MediaReviewThreadPolicy < OrganizationRecordPolicy
  def view?
    review_visible?
  end

  def create?
    return false unless review_visible?
    return true if user.internal?

    record.media_review.open? && customer_review_owner?
  end

  def update?
    review_visible? && (user.internal? || (record.media_review.open? && customer_review_owner?))
  end

  def manage?
    review_visible? && user.internal?
  end

  private

  def review_visible?
    record.media_review.present? && MediaReviewPolicy.new(user, record.media_review).view?
  end

  def customer_review_owner?
    !user.internal? && user.client_account_ids.include?(record.media_review.client_account_id)
  end
end
