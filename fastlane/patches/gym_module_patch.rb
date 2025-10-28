# frozen_string_literal: true

# Monkey patch for Gym::Module.building_multiplatform_for_ios? method
# This patch modifies the method to correctly handle xros SDK

require 'gym'

# Thank you Gym
module Gym
  class << self
    # Override the building_multiplatform_for_ios? method
    alias original_building_multiplatform_for_ios? building_multiplatform_for_ios? if method_defined?(:building_multiplatform_for_ios?)

    def building_multiplatform_for_ios?
      # Modified condition from line 62 of gym/lib/gym/module.rb
      Gym.project.multiplatform? && Gym.project.ios? && %w[xros iphoneos iphonesimulator].include?(Gym.config[:sdk])
    end
  end
end

puts '[Gym Patch] Applied monkey patch for building_multiplatform_for_ios? to include xros SDK'
