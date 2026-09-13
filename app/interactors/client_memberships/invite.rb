module ClientMemberships
  # Adds an invited person to a client account. The provider-specific invitation
  # mechanism stays on User; this action owns the account membership and audit
  # transition around it.
  class Invite < ApplicationInteractor
    def call
      account = context.fetch(:account)
      actor = context.fetch(:actor)
      email = context.fetch(:email).to_s.strip.downcase
      name = context[:name].presence || email
      role = normalized_role(context[:role])

      membership = ClientMembership.transaction do
        user = account.organization.users.find_by("LOWER(email) = ?", email) || invite_user(account, actor, email, name, role)
        membership = account.client_memberships.find_or_initialize_by(user: user)
        # Someone already in the account keeps the access they have; only a new
        # membership starts as an invitation.
        membership.role = role
        membership.status = :invited if membership.new_record?
        membership.save!

        ActivityEvent.create!(
          organization: account.organization,
          actor:,
          subject: membership,
          event_type: "client_membership.invited",
          payload: { client_account_id: account.id, role: }
        )
        membership
      end

      context.set(:membership, membership)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "client_membership_invite_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        client_account_id: context[:account]&.id
      )
    end

    private

    def normalized_role(role)
      %w[admin member].include?(role.to_s) ? role.to_s : "member"
    end

    def invite_user(account, actor, email, name, role)
      user = User.invite!(
        { email:, name:, organization: account.organization, role: role == "admin" ? "client_admin" : "client_member" },
        actor
      )
      raise ActiveRecord::RecordInvalid, user if user.errors.any?

      user
    end
  end
end
