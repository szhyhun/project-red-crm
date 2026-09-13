class Api::V1::PushSubscriptionsController < Api::V1::BaseController
  # What the browser needs to subscribe: the server's public key, or nothing
  # when push is not set up here.
  def settings
    authorize PushSubscription, :create?
    render json: { push: { public_key: NotificationChannels::Push.public_key, subscribed: current_user.push_subscriptions.exists? } }
  end

  def create
    authorize PushSubscription, :create?
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    if subscription.persisted? && subscription.user_id != current_user.id
      return render json: { error: "push_subscription_owned_by_another_user" }, status: :unprocessable_content
    end

    subscription.assign_attributes(user: current_user, p256dh: subscription_params.dig(:keys, :p256dh),
                                   auth: subscription_params.dig(:keys, :auth), user_agent: request.user_agent.to_s.truncate(255))
    subscription.save ? head(:created) : render_validation_errors(subscription)
  end

  def destroy
    subscription = policy_scope(PushSubscription).find_by!(endpoint: params.require(:endpoint))
    authorize subscription, :destroy?
    subscription.destroy!
    head :no_content
  end

  private

  def subscription_params
    params.require(:subscription).permit(:endpoint, keys: %i[p256dh auth])
  end
end
