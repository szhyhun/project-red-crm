class Api::V1::Auth::SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :csrf

  def csrf
    render json: { csrf_token: form_authenticity_token }
  end

  def create
    user = User.find_by(email: params.require(:email).downcase)

    if user&.valid_password?(params.require(:password)) && user.active?
      sign_in(user)
      render json: { user: serialize_user(user), csrf_token: form_authenticity_token }
    else
      render json: { error: "invalid_credentials" }, status: :unauthorized
    end
  end

  def destroy
    sign_out(current_user) if current_user
    head :no_content
  end

  def show
    return render json: { error: "unauthenticated" }, status: :unauthorized unless current_user

    render json: { user: serialize_user(current_user) }
  end

  private

  def serialize_user(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      organization: { id: user.organization_id, name: user.organization.name, slug: user.organization.slug }
    }
  end
end
