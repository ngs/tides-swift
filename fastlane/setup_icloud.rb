# frozen_string_literal: true

# Creates the CloudKit container the app syncs its saved locations through and
# associates every bundle ID with it.
#
# Like App Groups, iCloud containers only exist in the legacy Developer Portal
# API, so this needs an Apple ID session (FASTLANE_USER / FASTLANE_PASSWORD /
# FASTLANE_SESSION) rather than the App Store Connect API key.
#
# Run once, then reissue the profiles so they carry the entitlement:
#   MATCH_READONLY=false MATCH_FORCE=true bundle exec fastlane ios release_match
#   MATCH_READONLY=false MATCH_FORCE=true bundle exec fastlane mac release_match

require 'spaceship'

CONTAINER_IDENTIFIER = 'iCloud.io.ngs.Tides'
CONTAINER_NAME = 'Tides'
# The app, the widget and the watch app all read the synced store.
IDENTIFIERS = %w[io.ngs.Tides io.ngs.Tides.widget io.ngs.Tides.watchkitapp].freeze

Spaceship::Portal.login(ENV.fetch('FASTLANE_USER'), ENV.fetch('FASTLANE_PASSWORD'))
Spaceship::Portal.client.team_id = ENV.fetch('PRODUCE_TEAM_ID', '3Y8APYUG2G')

container = Spaceship::Portal.cloud_container.find(CONTAINER_IDENTIFIER) ||
            Spaceship::Portal.cloud_container.create!(
              identifier: CONTAINER_IDENTIFIER,
              name: CONTAINER_NAME
            )
puts "container: #{container.identifier}"

IDENTIFIERS.each do |identifier|
  app = Spaceship::Portal.app.find(identifier)
  raise "App ID not found: #{identifier}" if app.nil?

  app.update_service(Spaceship::Portal.app_service.cloud.on)
  app.update_service(Spaceship::Portal.app_service.cloud_kit.cloud_kit)
  app.update_service(Spaceship::Portal.app_service.push_notification.on)
  app.associate_cloud_containers([container])
  puts "#{identifier} -> #{container.identifier} (CloudKit + push enabled)"
end
