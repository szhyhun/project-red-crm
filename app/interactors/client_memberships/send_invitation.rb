module ClientMemberships
  # Sends, or sends again, the email that turns a pending membership into
  # access. People brought in by an import already exist, so inviting them is
  # this step rather than creating anyone.
  class SendInvitation < ApplicationInteractor
    def call
      membership = context.fetch(:membership)
      actor = context.fetch(:actor)
      unless membership.invited?
        context.fail!(code: "client_membership_not_invited", message: "Only a pending invitation can be sent")
      end
      unless emailable?(membership.user)
        context.fail!(code: "client_membership_user_signed_in",
                      message: "This person already signs in; they can accept the invitation from their teams")
      end

      membership.user.invite!(actor)
      ActivityEvent.create!(
        organization: membership.client_account.organization,
        actor:,
        subject: membership,
        event_type: "client_membership.invitation_sent",
        payload: { client_account_id: membership.client_account_id }
      )

      context.set(:membership, membership)
    end

    private

    # Someone who already set a password accepts from their own teams list; an
    # invitation email would ask them to set it again.
    def emailable?(user)
      return false if user.invitation_accepted_at.present?

      user.invitation_sent_at.present? || user.origin == "aryeo"
    end
  end
end
