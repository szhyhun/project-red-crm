class MediaReviewThreadPolicy < OrganizationRecordPolicy
  def view?
    review_visible?
  end

  # Threads are started by the customer, inside their draft review.
  def create?
    review_visible? && customer_member? && review.open?
  end

  # Replying. A customer adds to their own draft, or answers once the review is
  # submitted. Staff answer only after submission: until then the thread is the
  # customer's private draft.
  def update?
    return false unless review_visible? && !review.outdated?
    return !review.open? if user.internal?

    customer_member?
  end

  # Resolving and reopening, as in a merge request, belongs to both sides once
  # the discussion is public.
  def manage?
    review_visible? && !review.open? && !review.outdated? && (user.internal? || customer_member?)
  end

  private

  def review
    record.media_review
  end

  def review_visible?
    review.present? && MediaReviewPolicy.new(user, review).view?
  end

  def customer_member?
    !user.internal? && user.client_account_ids.include?(review.client_account_id)
  end
end
