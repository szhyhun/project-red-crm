class Api::V1::Auth::RegistrationsController < ApplicationController
  def create
    organization = Organization.new(organization_params)
    user = organization.users.build(user_params.merge(role: :organization_admin))

    Organization.transaction do
      organization.save!
      user.save!
    end

    sign_in(user)
    CustomerNotifications.workspace_welcome(user)
    render json: {
      user: { id: user.id, name: user.name, email: user.email, role: user.role },
      organization: { id: organization.id, name: organization.name, slug: organization.slug },
      csrf_token: form_authenticity_token
    }, status: :created
  rescue ActiveRecord::RecordInvalid
    render json: {
      error: "validation_failed",
      details: { organization: organization.errors.to_hash, user: user.errors.to_hash }
    }, status: :unprocessable_entity
  end

  private

  def organization_params
    params.require(:organization).permit(:name, :slug)
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
