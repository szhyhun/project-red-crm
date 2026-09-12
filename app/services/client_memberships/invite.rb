module ClientMemberships
  # Invites a person into an account. A brand-new person is sent a Devise
  # invitation and accepts by setting a password; someone who already signs in
  # accepts the membership itself. Either way the membership starts as
  # `invited` and grants nothing until then.
  class Invite
    def initialize(account:, actor:, email:, name: nil, role: "member")
      @account = account
      @actor = actor
      @email = email.to_s.strip.downcase
      @name = name.presence || @email
      @role = %w[admin member].include?(role.to_s) ? role.to_s : "member"
    end

    def call
      ClientMembership.transaction do
        user = existing_user || invite_user
        membership = @account.client_memberships.find_or_initialize_by(user: user)
        # Someone already in the account keeps the access they have; only a new
        # membership starts as an invitation.
        membership.role = @role
        membership.status = :invited if membership.new_record?
        membership.save!

        ActivityEvent.create!(
          organization: @account.organization,
          actor: @actor,
          subject: membership,
          event_type: "client_membership.invited",
          payload: { client_account_id: @account.id, role: @role }
        )
        membership
      end
    end

    private

    def existing_user
      @account.organization.users.find_by("LOWER(email) = ?", @email)
    end

    def invite_user
      user = User.invite!({ email: @email, name: @name, organization: @account.organization, role: customer_role }, @actor)
      raise ActiveRecord::RecordInvalid, user if user.errors.any?

      user
    end

    def customer_role
      @role == "admin" ? "client_admin" : "client_member"
    end
  end
end
