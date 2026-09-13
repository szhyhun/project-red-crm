require "net/http"

module NotificationChannels
  # Sends a text message through Twilio's REST API. It is switched on by
  # setting TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM_NUMBER;
  # without them no SMS delivery is ever scheduled.
  class Sms
    class DeliveryFailed < StandardError; end

    def self.configured?
      %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER].all? { |key| ENV[key].present? }
    end

    # Keeps digits and a leading plus; a North American number without a
    # country code gets +1. Anything shorter than ten digits is not a phone.
    def self.normalize(phone)
      digits = phone.to_s.gsub(/[^\d+]/, "")
      return if digits.delete("+").length < 10

      return digits if digits.start_with?("+")

      digits.length == 10 ? "+1#{digits}" : "+#{digits}"
    end

    def deliver(to:, body:)
      sid = ENV.fetch("TWILIO_ACCOUNT_SID")
      uri = URI("https://api.twilio.com/2010-04-01/Accounts/#{sid}/Messages.json")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(sid, ENV.fetch("TWILIO_AUTH_TOKEN"))
      request.set_form_data("To" => to, "From" => ENV.fetch("TWILIO_FROM_NUMBER"), "Body" => body.truncate(320))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      raise DeliveryFailed, "Twilio answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response
    end
  end
end
