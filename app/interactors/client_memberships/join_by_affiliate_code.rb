module ClientMemberships
  # A customer who has a team's affiliate code joins that team as a member.
  # Someone removed from a team cannot use the code to walk back in.
  class JoinByAffiliateCode < ApplicationInteractor
    def call
      user = context.fetch(:user)
      code = context.fetch(:code).to_s.strip.downcase
      account = code.present? && user.organization.client_accounts.active.find_by("LOWER(affiliate_id) = ?", code)
      context.fail!(code: "affiliate_code_unknown", message: "No team uses that code") unless account

      membership = ClientMembership.transaction do
        membership = account.client_memberships.find_or_initialize_by(user:)
        if membership.revoked? || membership.archived?
          context.fail!(code: "affiliate_code_membership_ended", message: "Ask the team's admin to invite you back")
        end

        # A new row takes the column default of active, so ask what it was, not what it says.
        joined = membership.new_record? || membership.invited?
        if membership.invited?
          membership.accept!
        elsif membership.new_record?
          membership.update!(role: :member, status: :active, invitation_accepted_at: Time.current)
          membership.make_default! if user.client_memberships.active.where(is_default: true).none?
        end
        if joined
          ActivityEvent.create!(organization: account.organization, actor: user, subject: membership,
                                event_type: "client_membership.joined_by_affiliate_code",
                                payload: { client_account_id: account.id })
        end
        membership
      end

      context.set(:membership, membership)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(code: "affiliate_code_join_invalid", message: error.record.errors.full_messages.to_sentence,
                    original_error: error)
    end
  end
end
