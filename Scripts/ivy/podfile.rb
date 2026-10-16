#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Ivy additions to the upstream Podfile. Loaded by the Podfile; keeping them
# here keeps the changes to the Podfile itself to two lines.

require 'json'

IVY_CATALYST_DEPENDENCIES = File.join(__dir__, 'catalyst-dependencies.json')

# The libsignal archive Ivy uses contains the upstream iOS builds plus a Mac
# Catalyst build, so it has its own checksum. Only switch to it once it has
# been published.
def ivy_configure_environment
  pins = JSON.parse(File.read(IVY_CATALYST_DEPENDENCIES))
  libsignal = pins['libsignal']
  ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = libsignal['sha256'] if libsignal
end

# Lets every pod build for Mac Catalyst and points the prebuilt Rust libraries
# at their Catalyst builds.
def ivy_post_install(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['SUPPORTS_MACCATALYST'] = 'YES'
    end
  end

  Dir.glob('Pods/Target Support Files/**/*.xcconfig') do |path|
    xcconfig = File.read(path)
    updated = xcconfig.gsub('SUPPORTS_MACCATALYST = NO', 'SUPPORTS_MACCATALYST = YES')

    # This project builds for macOS only as Mac Catalyst.
    updated = updated.gsub(
      'CARGO_BUILD_TARGET[sdk=macosx*][arch=arm64] = aarch64-apple-darwin',
      'CARGO_BUILD_TARGET[sdk=macosx*][arch=arm64] = aarch64-apple-ios-macabi'
    )
    if File.basename(path).start_with?('SignalRingRTC') && !updated.include?('CARGO_BUILD_TARGET[sdk=macosx*]')
      updated += "\nCARGO_BUILD_TARGET[sdk=macosx*] = aarch64-apple-ios-macabi\n"
    end

    File.write(path, updated) if updated != xcconfig
  end

  # CocoaPods records the slices of vendored XCFrameworks, with their platform
  # variant and architectures, when it installs. That is before the Catalyst
  # slice of WebRTC is added, so add it to the slice list and lookup tables.
  Dir.glob('Pods/Target Support Files/**/*-xcframeworks.sh') do |path|
    script = File.read(path)
    File.write(path, ivy_add_webrtc_catalyst_slice(script))
  end
end

IVY_WEBRTC_CATALYST_SLICE = 'ios-arm64-maccatalyst'

def ivy_add_webrtc_catalyst_slice(script)
  return script unless script.include?('WebRTC.xcframework')
  return script if script.include?("WebRTC.xcframework/#{IVY_WEBRTC_CATALYST_SLICE})")

  updated = script.gsub(/(install_xcframework "[^"]*WebRTC\.xcframework" .*?)$/) do |line|
    "#{line} \"#{IVY_WEBRTC_CATALYST_SLICE}\""
  end
  { 'variant_for_slice' => 'maccatalyst', 'archs_for_slice' => 'arm64' }.each do |function, value|
    updated = updated.sub("#{function}()\n{\n  case \"$1\" in\n") do |head|
      head + "  WebRTC.xcframework/#{IVY_WEBRTC_CATALYST_SLICE})\n    echo \"#{value}\"\n    ;;\n"
    end
  end
  updated
end
