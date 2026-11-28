#!/usr/bin/env ruby
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Waits until App Store Connect has processed an uploaded build:
#
#   asc-wait.rb BUILD   BUILD is the run number, the part after the dot in
#                       CFBundleVersion (8.32 (1910.BUILD)).
#
# Apple checks the signature while it processes the build, so the run's
# certificate must stay valid until then (testflight.sh revokes it after).
# Exits 0 when the build is valid, 1 when Apple rejected it, and 2 when
# processing took longer than the wait; the certificate then stays.

require_relative 'asc'

BUNDLE_ID = 'io.github.kirikakaese.ivy'
WAIT_MINUTES = Integer(ENV.fetch('IVY_PROCESSING_WAIT_MINUTES', '45'))

build_number = ARGV[0] or ASC.fail_with('usage: asc-wait.rb BUILD')

# A failed request must not end the wait: any exit but 0 or 2 revokes the certificate
# while Apple may still be processing the build.
def apple_data(path)
  response = ASC.request(:get, path)
  return JSON.parse(response.body)['data'] if response.code.start_with?('2')

  puts "App Store Connect answered #{response.code}; trying again."
  nil
rescue StandardError => e
  puts "Couldn't reach App Store Connect (#{e.class}); trying again."
  nil
end

deadline = Time.now + (WAIT_MINUTES * 60)
app_id = nil
last_state = nil
loop do
  unless app_id
    apps = apple_data("/v1/apps?filter[bundleId]=#{BUNDLE_ID}")
    ASC.fail_with("No app with the bundle ID #{BUNDLE_ID}.") if apps&.empty?
    app_id = apps&.first&.dig('id')
  end
  builds = app_id && apple_data("/v1/builds?filter[app]=#{app_id}&sort=-uploadedDate&limit=20")
  if builds
    build = builds.find { |b| b.dig('attributes', 'version').to_s.split('.').last == build_number.to_s }
    state = build&.dig('attributes', 'processingState') || 'NOT_LISTED_YET'
    if state != last_state
      puts "Build #{build_number}: #{state}"
      last_state = state
    end
    case state
    when 'VALID'
      puts "Apple processed build #{build_number}; it's ready in TestFlight."
      exit 0
    when 'FAILED', 'INVALID'
      puts "::error::Apple rejected build #{build_number} (#{state}). App Store Connect > TestFlight shows why, and Apple sends an email."
      exit 1
    end
  end
  if Time.now > deadline
    puts "::warning::Apple hasn't finished processing build #{build_number} after #{WAIT_MINUTES} minutes. " \
         'The certificate stays so the build can still pass; revoke it later on developer.apple.com > Certificates.'
    exit 2
  end
  sleep 30
end
