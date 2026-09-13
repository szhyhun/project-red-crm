module ClientAccounts
  # Breaks one team into two by moving chosen people into a new team. The work
  # already done stays where it was done; the new team starts with the old
  # one's settings, and each side must be left with an admin to run it.
  class Split < ApplicationInteractor
    COPIED_SETTINGS = %i[brokerage_name brokerage_website website logo_url lock_downloads_before_payment
                         display_original_price suppress_payment_reminders billing_pays_externally
                         billing_visibility pricing_visibility downloads_visibility marketing_templates_visibility
                         notification_preferences order_form_id].freeze

    def call
      source = context.fetch(:account)
      actor = context.fetch(:actor)
      name = context.fetch(:name).to_s.strip
      moving = source.client_memberships.where(id: Array(context.fetch(:membership_ids))).to_a

      refuse("Only a team can be split; an agent's or brokerage's own account cannot") unless source.team?
      refuse("An archived team cannot be split") if source.archived?
      refuse("Choose at least one person to move") if moving.empty?
      staying = source.client_memberships.where.not(id: moving.map(&:id))
      refuse("The new team needs an active admin among the people moving") unless moving.any? { |membership| membership.active? && membership.admin? }
      refuse("#{source.name} must keep an active admin") unless staying.active.admin.exists?

      team = ClientAccount.transaction do
        team = source.organization.client_accounts.create!(
          source.slice(*COPIED_SETTINGS).merge(name:, kind: :team, origin: source.origin)
        )
        # A billing member who moves takes the bill with them.
        billing_user_id = source.billing_user_id if moving.any? { |membership| membership.user_id == source.billing_user_id }
        source.update!(billing_user: nil) if billing_user_id
        moving.each { |membership| membership.update!(client_account: team) }
        team.update!(billing_user_id:) if billing_user_id

        [ source, team ].each do |subject|
          ActivityEvent.create!(organization: source.organization, actor:, subject:, event_type: "client_account.split",
                                payload: { from_client_account_id: source.id, to_client_account_id: team.id,
                                           user_ids: moving.map(&:user_id) })
        end
        team
      end

      context.set(:team, team)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(code: "client_account_split_invalid", message: error.record.errors.full_messages.to_sentence,
                    original_error: error, client_account_id: context[:account]&.id)
    end

    private

    def refuse(message)
      context.fail!(code: "client_account_split_refused", message:)
    end
  end
end
