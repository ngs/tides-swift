# frozen_string_literal: true

# Enables the App Groups capability on the app and widget bundle IDs.
#
# The App Store Connect API can toggle the capability but cannot associate a
# bundle ID with a specific App Group - that relationship only exists in the
# legacy Developer Portal API, which needs an Apple ID login. Run this, then
# assign group.io.ngs.Tides to both identifiers (portal or an Apple ID
# session), then reissue the profiles with `fastlane ios release_match`.

require 'spaceship'

IDENTIFIERS = %w[io.ngs.Tides io.ngs.Tides.widget].freeze

token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch('APP_STORE_CONNECT_API_KEY_KEY_ID'),
  issuer_id: ENV.fetch('APP_STORE_CONNECT_API_KEY_ISSUER_ID'),
  key: Base64.decode64(ENV.fetch('APP_STORE_CONNECT_API_KEY_KEY'))
)
Spaceship::ConnectAPI.token = token

IDENTIFIERS.each do |identifier|
  bundle_id = Spaceship::ConnectAPI::BundleId.find(identifier)
  raise "bundle id not found: #{identifier}" if bundle_id.nil?

  enabled = bundle_id.get_capabilities.any? do |capability|
    capability.capability_type == Spaceship::ConnectAPI::BundleIdCapability::Type::APP_GROUPS
  end

  if enabled
    puts "#{identifier}: App Groups capability already enabled"
    next
  end

  bundle_id.create_capability(Spaceship::ConnectAPI::BundleIdCapability::Type::APP_GROUPS)
  puts "#{identifier}: enabled App Groups capability"
end
