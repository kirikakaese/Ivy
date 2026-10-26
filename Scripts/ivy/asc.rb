#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Talks to the App Store Connect API with the team's API key, for the
# TestFlight scripts.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'

module ASC
  module_function

  def fail_with(message)
    puts "::error::#{message}"
    exit 1
  end

  def key_id = ENV.fetch('ASC_KEY_ID').strip
  def issuer_id = ENV.fetch('ASC_ISSUER_ID').strip

  # The key as a clean .p8 text. Pasted keys sometimes lose their line
  # breaks or carry escaped ones.
  def key_pem
    text = ENV.fetch('ASC_KEY').strip.gsub('\\n', "\n").gsub("\r", '')
    body = text.gsub(/-----(BEGIN|END) PRIVATE KEY-----/, '').gsub(/\s+/, '')
    "-----BEGIN PRIVATE KEY-----\n#{body.scan(/.{1,64}/).join("\n")}\n-----END PRIVATE KEY-----\n"
  end

  def key
    @key ||= OpenSSL::PKey::EC.new(key_pem)
  rescue OpenSSL::PKey::PKeyError
    fail_with('ASC_KEY is not a readable .p8 key. Paste the whole text of AuthKey_<Key ID>.p8, including the BEGIN and END lines.')
  end

  def b64(data) = Base64.urlsafe_encode64(data, padding: false)

  # A token lives 10 minutes; a new one is made for every request.
  def token
    now = Time.now.to_i
    signing_input = [
      b64({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json),
      b64({ iss: issuer_id, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }.to_json),
    ].join('.')
    der = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
    r, s = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0") }
    "#{signing_input}.#{b64(r + s)}"
  end

  def request(method, path, body = nil)
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    request = Net::HTTP.const_get(method.capitalize).new(uri)
    request['Authorization'] = "Bearer #{token}"
    if body
      request['Content-Type'] = 'application/json'
      request.body = body.to_json
    end
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  end

  def apple_says(response)
    JSON.parse(response.body).fetch('errors', []).map { |e| e['detail'] || e['title'] }.compact.join(' ')
  rescue JSON::ParserError
    response.body.to_s[0, 300]
  end

  # The response's JSON, or a clear stop with Apple's reason.
  def call(method, path, body = nil, what:)
    response = request(method, path, body)
    return (response.body.to_s.empty? ? {} : JSON.parse(response.body)) if response.code.start_with?('2')

    fail_with("Couldn't #{what} (#{response.code}): #{apple_says(response)}")
  end
end
