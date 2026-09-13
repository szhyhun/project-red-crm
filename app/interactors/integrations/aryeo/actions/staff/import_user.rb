module Integrations::Aryeo::Actions::Staff
  class ImportUser < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        email = importer.staff_value(payload, "email", "email_address").to_s.downcase
        return context.set(:user, nil) if email.blank?

        user = importer.organization.users.find_by(email:)
        user ||= User.find_by(email: email)
        return context.set(:user, user) if user&.organization_id == importer.organization.id
        return context.set(:user, nil) if user.present?

        password = SecureRandom.urlsafe_base64(32)
        user = importer.organization.users.create!(
          name: importer.staff_person_name(payload).presence || email.split("@").first,
          email:,
          role: :production_staff,
          status: :suspended,
          password:,
          password_confirmation: password,
          origin: :aryeo
        )
        context.set(:user, user)
      end
  end
end
