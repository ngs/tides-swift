# frozen_string_literal: true

# Monkey patch for Gym::Module.building_multiplatform_for_ios? method.
# Two changes over stock gym:
#  - xros counts as an iOS-family SDK (visionOS archives package like iOS)
#  - the destination is consulted as well, so lanes can omit `sdk:`.
#    Passing `-sdk` to xcodebuild forces it on every target in the build,
#    which breaks embedded targets of another platform (the watch app).

require 'gym'

# Thank you Gym
module Gym
  class << self
    # Override the building_multiplatform_for_ios? method
    alias original_building_multiplatform_for_ios? building_multiplatform_for_ios? if method_defined?(:building_multiplatform_for_ios?)

    def building_multiplatform_for_ios?
      # Modified condition from line 62 of gym/lib/gym/module.rb
      return false unless Gym.project.multiplatform? && Gym.project.ios?

      %w[xros iphoneos iphonesimulator].include?(Gym.config[:sdk]) ||
        Gym.config[:destination].to_s.match?(/platform=(iOS|visionOS)/)
    end
  end
end

puts '[Gym Patch] Applied monkey patch for building_multiplatform_for_ios? (xros SDK / destination detection)'
