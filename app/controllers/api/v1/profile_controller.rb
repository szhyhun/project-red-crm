class Api::V1::ProfileController < Api::V1::BaseController
  def show
    authorize current_user, :view?
    render json: { profile: serialize(current_user) }
  end

  def update
    authorize current_user, :update?

    saved = password_change? ? change_password : current_user.update(details_params)
    return render_validation_errors(current_user) unless saved

    bypass_sign_in(current_user) if password_change?
    render json: { profile: serialize(current_user.reload) }
  end

  private

  # Role and status are deliberately absent: those are decided for you, not by
  # you, and the staff screen is where an administrator changes them.
  def details_params
    params.require(:profile).permit(:name, :email)
  end

  def password_change?
    params.require(:profile)[:password].present?
  end

  # Devise checks the current password itself, so a stolen session cannot
  # quietly change the password and lock the owner out.
  def change_password
    current_user.update_with_password(
      params.require(:profile).permit(:password, :password_confirmation, :current_password)
    )
  end

  def serialize(user)
    user.slice(:id, :name, :email, :role, :status).merge(
      organization: user.organization.slice(:id, :name, :slug),
      capabilities: capabilities_for(user)
    )
  end
end
