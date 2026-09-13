class Api::V1::Auth::PasswordsController < ApplicationController
  # Finishes a reset from the link in the email. The token is the only proof,
  # so a wrong or used one gets the same answer as an expired one.
  def update
    user = User.reset_password_by_token(
      reset_password_token: params.require(:reset_password_token),
      password: params.require(:password),
      password_confirmation: params.require(:password_confirmation)
    )

    if user.errors.empty?
      render json: { reset: true }
    else
      render json: { error: "password_reset_invalid", details: user.errors.to_hash }, status: :unprocessable_content
    end
  end
end
