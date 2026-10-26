#!/usr/bin/env ruby
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Checks the App Store Connect API key before the long build: that the key
# reads, that Apple accepts it, and that the app record exists. Prints what
# to fix instead of a signing error an hour later.

require_relative 'asc'

bundle_id = ENV.fetch('IVY_BUNDLE_ID')

ASC.key
ASC.fail_with("ASC_KEY_ID should be 10 characters, it has #{ASC.key_id.length}.") unless ASC.key_id.length == 10
unless ASC.issuer_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
  ASC.fail_with('ASC_ISSUER_ID should look like 69a6de7e-xxxx-xxxx-xxxx-xxxxxxxxxxxx (the Issuer ID above the list of team keys).')
end

response = ASC.request(:get, "/v1/apps?filter[bundleId]=#{bundle_id}")
case response.code
when '200'
  apps = JSON.parse(response.body).fetch('data')
  if apps.empty?
    ASC.fail_with("Apple accepts the key, but there is no app with the bundle ID #{bundle_id} in App Store Connect (docs/TESTFLIGHT.md, step 4).")
  end
  puts "API key works; app record found: #{apps.first.dig('attributes', 'name')}"
when '401'
  ASC.fail_with('Apple rejects the key (401). Check that ASC_KEY_ID is the Key ID of this .p8, that ASC_ISSUER_ID is the Issuer ID above the team keys, and that the key is a Team key, not an Individual key, and not revoked.')
else
  ASC.fail_with("App Store Connect answered #{response.code}: #{ASC.apple_says(response)}")
end

# Signing needs the developer side of the account too: certificates, App
# IDs and profiles. Apple refuses these to keys without the Admin role and
# while an agreement waits to be accepted.
{
  'certificates' => '/v1/certificates?limit=1',
  'App IDs' => "/v1/bundleIds?filter[identifier]=#{bundle_id}",
  'profiles' => '/v1/profiles?limit=1',
}.each do |what, path|
  response = ASC.request(:get, path)
  next if response.code == '200'

  detail = ASC.apple_says(response)
  hint = if detail.match?(/agreement/i)
    'Accept the pending agreement on developer.apple.com/account and in App Store Connect > Business.'
  elsif response.code == '403'
    'Give the API key the Admin role (App Store Connect > Users and Access > Integrations), or create a new Admin key.'
  else
    ''
  end
  ASC.fail_with("The key may not read #{what} (#{response.code}): #{detail} #{hint}".strip)
end
puts 'The key may manage certificates, App IDs and profiles.'
