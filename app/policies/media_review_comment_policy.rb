class MediaReviewCommentPolicy < OrganizationRecordPolicy
  def view?
    thread_visible?
  end

  def create?
    thread.present? && MediaReviewThreadPolicy.new(user, thread).update?
  end

  # Only an unsent draft can change. A published comment is part of the record
  # the other side has already read and answered.
  def update?
    thread_visible? && record.author_id == user.id && record.draft? && thread.media_review.open?
  end

  def destroy?
    update?
  end

  def manage?
    thread_visible? && user.internal?
  end

  private

  def thread
    record.media_review_thread
  end

  def thread_visible?
    thread.present? && MediaReviewThreadPolicy.new(user, thread).view?
  end
end
