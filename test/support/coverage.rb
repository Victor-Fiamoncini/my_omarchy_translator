# frozen_string_literal: true

# Line and branch coverage with SimpleCov, on when COVERAGE is set (bin/ci sets it).
#
# The CLI tests run bin/omarchy-translate in a child process, which the test process can't
# see. CoverageSupport.env loads this file into those children through RUBYOPT; each child
# stores its own result, and SimpleCov merges them all into coverage/ when the suite ends.
module CoverageSupport
  ENABLED = !ENV['COVERAGE'].to_s.empty?
  CHILD = 'COVERAGE_CHILD'

  # Extra environment for a Ruby child process whose coverage should count.
  def self.env
    return {} unless ENABLED

    { 'RUBYOPT' => "#{ENV.fetch('RUBYOPT', nil)} -r#{__FILE__}".strip, CHILD => '1' }
  end
end

if CoverageSupport::ENABLED
  require 'simplecov'

  child = ENV.delete(CoverageSupport::CHILD)
  # Processes the child spawns in turn (the fake `claude` CLI) are not ours to measure.
  ENV.delete('RUBYOPT') if child

  SimpleCov.start do
    root File.expand_path('../..', __dir__)
    enable_coverage :branch
    # Also lists files no test loads, and keeps test/ and bin/ci out of the report.
    cover '{bin/omarchy-translate,lib/**/*.rb}'
    group 'CLI', 'bin/'
    group 'Providers', 'lib/omarchy_translator/providers/'
    command_name child ? "cli #{Process.pid}" : 'minitest'
    next if child

    # The floor of the current numbers: raise it as tests are added, never lower it.
    minimum_coverage line: 96, branch: 85
  end

  # A child only stores its result for the merge; the test process reports and enforces the minimum.
  SimpleCov.at_exit { SimpleCov.result } if child
end
