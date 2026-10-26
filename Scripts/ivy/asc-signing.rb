#!/usr/bin/env ruby
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Signing for one TestFlight run, through the App Store Connect API:
#
#   asc-signing.rb prepare DIR   App IDs with their capabilities, a
#                                distribution certificate (DIR/signing.cer,
#                                DIR/signing-key.pem)
#                                and an App Store profile per App ID
#                                (DIR/profiles), named "Ivy CI <bundle ID>".
#   asc-signing.rb cleanup DIR   Revokes that certificate and deletes the
#                                profiles. Uploaded builds stay valid.

require_relative 'asc'
require 'fileutils'

PREFIX = 'io.github.kirikakaese.ivy'
APP_GROUP = "group.#{PREFIX}.group"
# The app and the extensions it embeds, and whether each uses data protection.
TARGETS = {
  PREFIX => ['Ivy', true],
  "#{PREFIX}.SignalNSE" => ['Ivy Notification Service', true],
  "#{PREFIX}.shareextension" => ['Ivy Share Extension', true],
  "#{PREFIX}.widgets" => ['Ivy Widgets', false],
}.freeze

def profile_name(bundle_id) = "Ivy CI #{bundle_id}"

def bundle_id_record(identifier, name)
  found = ASC.call(:get, "/v1/bundleIds?filter[identifier]=#{identifier}&limit=200", what: 'list App IDs')
  record = found['data'].find { |b| b.dig('attributes', 'identifier') == identifier }
  return record['id'] if record

  created = ASC.call(:post, '/v1/bundleIds', {
    data: { type: 'bundleIds', attributes: { identifier: identifier, name: name, platform: 'IOS' } },
  }, what: "create the App ID #{identifier}")
  puts "Created the App ID #{identifier}"
  created['data']['id']
end

def ensure_capability(bundle_record_id, identifier, type, settings = nil)
  existing = ASC.call(:get, "/v1/bundleIds/#{bundle_record_id}/bundleIdCapabilities", what: "read the capabilities of #{identifier}")
  return if existing['data'].any? { |c| c.dig('attributes', 'capabilityType') == type }

  attributes = { capabilityType: type }
  attributes[:settings] = settings if settings
  ASC.call(:post, '/v1/bundleIdCapabilities', {
    data: {
      type: 'bundleIdCapabilities',
      attributes: attributes,
      relationships: { bundleId: { data: { type: 'bundleIds', id: bundle_record_id } } },
    },
  }, what: "turn on #{type} for #{identifier}")
  puts "Turned on #{type} for #{identifier}"
end

def prepare(dir)
  FileUtils.mkdir_p(File.join(dir, 'profiles'))
  state = { 'certificate' => nil, 'profiles' => [] }
  state_path = File.join(dir, 'signing.json')

  records = TARGETS.to_h do |identifier, (name, data_protection)|
    record_id = bundle_id_record(identifier, name)
    ensure_capability(record_id, identifier, 'APP_GROUPS')
    if data_protection
      ensure_capability(record_id, identifier, 'DATA_PROTECTION', [{
        key: 'DATA_PROTECTION_PERMISSION_LEVEL', options: [{ key: 'COMPLETE_PROTECTION' }],
      }])
    end
    [identifier, record_id]
  end

  # A certificate only for this run.
  private_key = OpenSSL::PKey::RSA.new(2048)
  csr = OpenSSL::X509::Request.new
  csr.version = 0
  csr.subject = OpenSSL::X509::Name.new([['CN', 'Ivy CI'], ['O', 'Ivy']])
  csr.public_key = private_key
  csr.sign(private_key, OpenSSL::Digest.new('SHA256'))
  response = ASC.request(:post, '/v1/certificates', {
    data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent: csr.to_pem } },
  })
  unless response.code.start_with?('2')
    ASC.fail_with("Couldn't create a distribution certificate (#{response.code}): #{ASC.apple_says(response)} " \
                  'If the team has too many, revoke unused ones on developer.apple.com > Certificates.')
  end
  certificate = JSON.parse(response.body)['data']
  state['certificate'] = certificate['id']
  File.write(state_path, state.to_json)
  cert = OpenSSL::X509::Certificate.new(Base64.decode64(certificate.dig('attributes', 'certificateContent')))
  # Key and certificate go into the keychain separately; macOS can't read
  # every .p12 that current OpenSSL writes.
  File.write(File.join(dir, 'signing-key.pem'), private_key.to_pem, perm: 0o600)
  File.binwrite(File.join(dir, 'signing.cer'), cert.to_der)
  puts "Created a distribution certificate (#{cert.subject})"

  # Profiles from an earlier run that didn't clean up go first.
  TARGETS.each_key do |identifier|
    old = ASC.call(:get, "/v1/profiles?filter[name]=#{URI.encode_www_form_component(profile_name(identifier))}", what: 'list profiles')
    old['data'].each { |p| ASC.call(:delete, "/v1/profiles/#{p['id']}", what: 'delete an old profile') }
  end

  records.each do |identifier, record_id|
    profile = ASC.call(:post, '/v1/profiles', {
      data: {
        type: 'profiles',
        attributes: { name: profile_name(identifier), profileType: 'IOS_APP_STORE' },
        relationships: {
          bundleId: { data: { type: 'bundleIds', id: record_id } },
          certificates: { data: [{ type: 'certificates', id: certificate['id'] }] },
        },
      },
    }, what: "create the App Store profile for #{identifier}")['data']
    state['profiles'] << profile['id']
    File.write(state_path, state.to_json)
    File.binwrite(File.join(dir, 'profiles', "#{identifier}.mobileprovision"),
                  Base64.decode64(profile.dig('attributes', 'profileContent')))
    puts "Created the profile #{profile_name(identifier)}"
  end
end

def cleanup(dir)
  state_path = File.join(dir, 'signing.json')
  return unless File.exist?(state_path)

  state = JSON.parse(File.read(state_path))
  state['profiles'].each { |id| ASC.request(:delete, "/v1/profiles/#{id}") }
  ASC.request(:delete, "/v1/certificates/#{state['certificate']}") if state['certificate']
  puts 'Revoked the run\'s certificate and deleted its profiles.'
end

command, dir = ARGV
case command
when 'prepare' then prepare(dir)
when 'cleanup' then cleanup(dir)
else ASC.fail_with('usage: asc-signing.rb prepare|cleanup DIR')
end
