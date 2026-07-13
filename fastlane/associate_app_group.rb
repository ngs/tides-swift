# frozen_string_literal: true

# Associates the app and widget bundle IDs with the shared App Group.
#
# The App Store Connect API can enable the App Groups capability but cannot say
# *which* group a bundle ID belongs to - that relationship only exists in the
# legacy Developer Portal API, so this needs an Apple ID session
# (FASTLANE_USER / FASTLANE_PASSWORD / FASTLANE_SESSION).
#
# Run this once, then reissue the profiles so they carry the entitlement:
#   MATCH_READONLY=false bundle exec fastlane ios release_match

require 'spaceship'

GROUP_IDENTIFIER = 'group.io.ngs.Tides'
IDENTIFIERS = %w[io.ngs.Tides io.ngs.Tides.widget].freeze

Spaceship::Portal.login(ENV.fetch('FASTLANE_USER'), ENV.fetch('FASTLANE_PASSWORD'))
Spaceship::Portal.client.team_id = ENV.fetch('PRODUCE_TEAM_ID', '3Y8APYUG2G')

group = Spaceship::Portal.app_group.find(GROUP_IDENTIFIER)
raise "App group not found: #{GROUP_IDENTIFIER}" if group.nil?

IDENTIFIERS.each do |identifier|
  app = Spaceship::Portal.app.find(identifier)
  raise "App ID not found: #{identifier}" if app.nil?

  app.associate_groups([group])
  puts "#{identifier} -> #{group.group_id}"
end
