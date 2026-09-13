class Api::V1::ClientAccountNotificationsController < Api::V1::BaseController
  def show
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :view?

    render json: serialize(account)
  end

  # One field on one record: which events the team is told about, on which channel.
  def update
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :configure_notifications?

    if account.update(notification_preferences: preferences)
      ActivityEvent.create!(organization: account.organization, actor: current_user, subject: account,
                            event_type: "client_account.notifications_changed")
      render json: serialize(account)
    else
      render_validation_errors(account)
    end
  end

  private

  def preferences
    raw = params.require(:client_account).fetch(:notification_preferences, {})
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    raw.to_h.transform_values do |channels|
      channels.to_h.transform_values { |enabled| ActiveModel::Type::Boolean.new.cast(enabled) }
    end
  end

  def serialize(account)
    delivered_channels = [ "email" ]
    delivered_channels << "sms" if NotificationChannels::Sms.configured?
    delivered_channels << "push" if NotificationChannels::Push.configured?

    {
      notifications: {
        events: ClientAccount::NOTIFICATION_EVENTS,
        channels: ClientAccount::NOTIFICATION_CHANNELS,
        delivered_channels: delivered_channels,
        matrix: ClientAccount::NOTIFICATION_EVENTS.index_with do |event|
          ClientAccount::NOTIFICATION_CHANNELS.index_with { |channel| account.notify?(event, channel) }
        end,
        capabilities: ClientAccountPolicy.new(current_user, account).capabilities
      }
    }
  end
end
