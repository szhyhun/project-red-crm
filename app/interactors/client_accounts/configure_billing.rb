module ClientAccounts
  # Decides who pays for a team and what its customers may read. Naming a
  # billing member makes them an admin in the same transaction, because a bill
  # addressed to someone who cannot see it is not a bill anyone will pay.
  class ConfigureBilling < ApplicationInteractor
    ATTRIBUTES = %i[billing_user_id billing_pays_externally billing_visibility pricing_visibility
                    downloads_visibility marketing_templates_visibility].freeze

    def call
      account = context.fetch(:account)
      actor = context.fetch(:actor)
      attributes = context.fetch(:attributes).to_h.symbolize_keys.slice(*ATTRIBUTES)

      ClientAccount.transaction do
        promote_billing_member(account, attributes[:billing_user_id]) if attributes.key?(:billing_user_id)
        account.update!(attributes)

        ActivityEvent.create!(
          organization: account.organization,
          actor:,
          subject: account,
          event_type: "client_account.billing_configured",
          payload: { changed: account.previous_changes.keys - %w[updated_at], billing_user_id: account.billing_user_id }
        )
      end

      context.set(:account, account)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "client_account_billing_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        client_account_id: context[:account]&.id
      )
    end

    private

    def promote_billing_member(account, user_id)
      return if user_id.blank?

      membership = account.client_memberships.active.find_by(user_id:)
      return if membership.blank? # the account validation names the problem

      membership.update!(role: :admin) unless membership.admin?
    end
  end
end
