#!/usr/bin/env ruby
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Checks the App Store Connect API key before the long build: that the key
# reads, that Apple accepts it, and that the app record exists. Prints what
# to fix instead of a signing error an hour later. Writes the cleaned-up key
# to the path given as the first argument.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'

def fail_with(message)
  puts "::error::#{message}"
  exit 1
end

key_path = ARGV.fetch(0)
key_id = ENV.fetch('ASC_KEY_ID').strip
issuer_id = ENV.fetch('ASC_ISSUER_ID').strip
bundle_id = ENV.fetch('IVY_BUNDLE_ID')

# Pasted keys sometimes lose their line breaks or carry escaped ones.
text = ENV.fetch('ASC_KEY').strip.gsub('\\n', "\n").gsub("\r", '')
body = text.gsub(/-----(BEGIN|END) PRIVATE KEY-----/, '').gsub(/\s+/, '')
pem = "-----BEGIN PRIVATE KEY-----\n#{body.scan(/.{1,64}/).join("\n")}\n-----END PRIVATE KEY-----\n"
begin
  key = OpenSSL::PKey::EC.new(pem)
rescue OpenSSL::PKey::PKeyError
  fail_with('ASC_KEY is not a readable .p8 key. Paste the whole text of AuthKey_<Key ID>.p8, including the BEGIN and END lines.')
end
File.write(key_path, pem, perm: 0o600)

fail_with("ASC_KEY_ID should be 10 characters, it has #{key_id.length}.") unless key_id.length == 10
unless issuer_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
  fail_with('ASC_ISSUER_ID should look like 69a6de7e-xxxx-xxxx-xxxx-xxxxxxxxxxxx (the Issuer ID above the list of team keys).')
end

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

now = Time.now.to_i
signing_input = [
  b64({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json),
  b64({ iss: issuer_id, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }.to_json),
].join('.')
der = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
r, s = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0") }
token = "#{signing_input}.#{b64(r + s)}"

def get(path, token)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{token}"
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
end

def apple_says(response)
  JSON.parse(response.body).fetch('errors', []).map { |e| e['detail'] || e['title'] }.compact.join(' ')
rescue JSON::ParserError
  response.body[0, 300]
end

response = get("/v1/apps?filter[bundleId]=#{bundle_id}", token)
case response.code
when '200'
  apps = JSON.parse(response.body).fetch('data')
  if apps.empty?
    fail_with("Apple accepts the key, but there is no app with the bundle ID #{bundle_id} in App Store Connect (docs/TESTFLIGHT.md, step 4).")
  end
  puts "API key works; app record found: #{apps.first.dig('attributes', 'name')}"
when '401'
  fail_with('Apple rejects the key (401). Check that ASC_KEY_ID is the Key ID of this .p8, that ASC_ISSUER_ID is the Issuer ID above the team keys, and that the key is a Team key, not an Individual key, and not revoked.')
else
  fail_with("App Store Connect answered #{response.code}: #{apple_says(response)}")
end

# Signing needs the developer side of the account too: certificates, App
# IDs and profiles. Apple refuses these to keys without the Admin role and
# while an agreement waits to be accepted.
{
  'certificates' => '/v1/certificates?limit=1',
  'App IDs' => "/v1/bundleIds?filter[identifier]=#{bundle_id}",
  'profiles' => '/v1/profiles?limit=1',
}.each do |what, path|
  response = get(path, token)
  next if response.code == '200'
  detail = apple_says(response)
  hint = if detail.match?(/agreement/i)
    'Accept the pending agreement on developer.apple.com/account and in App Store Connect > Business.'
  elsif response.code == '403'
    'Give the API key the Admin role (App Store Connect > Users and Access > Integrations), or create a new Admin key.'
  else
    ''
  end
  fail_with("The key may not read #{what} (#{response.code}): #{detail} #{hint}".strip)
end
puts 'The key may manage certificates, App IDs and profiles.'
