require "net/http"
require "json"
require "securerandom"
require "openssl"

class BrevoDelivery
  ENDPOINT = URI("https://api.brevo.com/v3/smtp/email").freeze
  class Failed < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("Recovery email could not be requested (#{reason}).")
    end
  end

  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    raise Failed, :configuration if @settings[:api_key].to_s.empty?
    raise Failed, :content unless mail.html_part && mail.text_part && mail.to&.length == 1
    html = mail.html_part.body.decoded
    mail.attachments.each do |attachment|
      raise Failed, :content unless attachment.inline? && attachment.filename == "lefty-wefty.png"
      html = html.gsub(attachment.url, "#{@settings.fetch(:origin)}/brand/logos/email-logo.png")
    end
    sender = Mail::Address.new(mail.from.first)
    payload = {
      sender: { email: sender.address, name: "Lefty-Wefty" },
      to: mail.to.map { |address| { email: address } },
      subject: mail.subject,
      htmlContent: html,
      textContent: mail.text_part.body.decoded,
      headers: { "idempotencyKey" => SecureRandom.uuid }
    }
    request = Net::HTTP::Post.new(ENDPOINT)
    request["api-key"] = @settings.fetch(:api_key)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(payload)
    2.times do |attempt|
      response = send_request(request)
      if response.code.to_i == 201
        raise Failed, :response if response.body.to_s.bytesize > 65_536
        result = JSON.parse(response.body)
        unless result.is_a?(Hash) && result["messageId"].is_a?(String) && !result["messageId"].empty?
          raise Failed, :response
        end
        return mail
      end
      # Retry only an explicit throttle rejection, never an ambiguous timeout.
      delay = response["Retry-After"].to_s
      if response.code.to_i == 429 && attempt.zero? && (delay.empty? || delay.match?(/\A[01]\z/))
        pause(delay.empty? ? 0.2 : delay.to_i)
        next
      end
      raise Failed, response.code.to_i == 429 ? :rate_limited : :rejected
    end
  rescue JSON::ParserError
    raise Failed, :response
  rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
    raise Failed, :connection
  end

  private
    def send_request(request)
      http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 3
      http.read_timeout = 5
      http.write_timeout = 3
      http.max_retries = 0
      http.start { |connection| connection.request(request) }
    end

    def pause(seconds)
      sleep(seconds)
    end
end
