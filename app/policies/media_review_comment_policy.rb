class MediaReviewCommentPolicy < OrganizationRecordPolicy
  def view?
    thread_visible?
  end

  def create?
    return false unless thread_visible?
    return true if user.internal?

    record.media_review_thread.media_review.open? && own_draft_author?
  end

  def update?
    thread_visible? && record.author_id == user.id && record.draft? && record.media_review_thread.media_review.open?
  end

  def destroy?
    update?
  end

  def manage?
    thread_visible? && user.internal?
  end

  private

  def thread_visible?
    record.media_review_thread.present? && MediaReviewThreadPolicy.new(user, record.media_review_thread).view?
  end

  def own_draft_author?
    record.author_id == user.id || user.client_account_ids.include?(record.media_review_thread.media_review.client_account_id)
  end
end
