require "uri"

class PublicSite
  NAME = "Lefty-Wefty"
  TITLE = "Lefty-Wefty | Stock and sales for small businesses"
  DESCRIPTION = "Keep track of products, stock and sales with Lefty-Wefty. Record sales, spot low stock and see monthly totals in one simple workspace."
  IMAGE_ALT = "Lefty-Wefty shop symbol and wordmark with the phrase Stock and sales, in order."

  def self.origin
    uri = URI.parse(Rails.application.config.x.public_origin.to_s)
    return unless uri.is_a?(URI::HTTPS) && uri.host && uri.port == 443
    return if uri.userinfo || uri.query || uri.fragment || ![ "", "/" ].include?(uri.path)
    return unless uri.host.match?(/\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/i)
    reserved = uri.host.match?(/(?:\A|\.)(?:localhost|test|example|invalid)\z/i) || uri.host.match?(/\A(?:.*\.)?example\.(?:com|org|net)\z/i)
    return if reserved && !Rails.env.test?
    "https://#{uri.host.downcase}"
  rescue URI::InvalidURIError
    nil
  end

  def self.indexing?
    Rails.application.config.x.public_indexing == true && origin.present?
  end

  def self.indexing_for?(request)
    indexing? && (!Rails.env.production? || request.host.downcase == URI.parse(origin).host)
  end

  def self.url(path = "/")
    "#{origin}#{path}" if indexing?
  end
end
