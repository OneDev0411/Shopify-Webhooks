# frozen_string_literal: true

# spec/support/request_helpers.rb
module RequestHelpers
  def parse_json
    @parse_json ||= JSON.parse(response.body)
  end

  def load_payload(payload)
    File.read("#{Rails.root.join(*%w( spec support payloads))}/#{payload}.json")
  end

  def webhook_headers(shopify_domain, webhook_payload)
    digest = OpenSSL::Digest.new('sha256')
    calculated_hmac =
      Base64.encode64(OpenSSL::HMAC.digest(digest, ENV['SHOPIFY_APP_SECRET'], webhook_payload.to_s)).strip
    {
      'HTTP_X_SHOPIFY_HMAC_SHA256' => calculated_hmac,
      'CONTENT_TYPE' => 'application/json; charset=utf-8',
      'ACCEPT' => 'application/json',
      'HTTP_X_SHOPIFY_SHOP_DOMAIN' => shopify_domain
     }
  end
end
