# frozen_string_literal: true

# First, so SimpleCov sees lib/ being loaded.
require_relative 'support/coverage'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/omarchy_translator'
require_relative 'support/fake_api'
require_relative 'support/fake_claude'
