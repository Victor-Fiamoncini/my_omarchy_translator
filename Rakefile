# frozen_string_literal: true

require 'minitest/test_task'
require 'rubocop/rake_task'

Minitest::TestTask.create(:test) do |t|
  t.test_globs = ['test/**/*_test.rb']
end

RuboCop::RakeTask.new(:lint)

desc 'Lint QML with qmllint against the Omarchy shell modules'
task :qml do
  sh 'script/lint-qml'
end

desc 'Run the QML tests (PanelLogic.js) with qmltestrunner'
task :qml_test do
  sh 'script/test-qml'
end

desc 'Check .editorconfig formatting on the files RuboCop does not cover'
task :format do
  sh 'script/check-format'
end

desc 'Validate the Omarchy plugin manifest'
task :validate do
  sh 'omarchy plugin validate .'
end

desc 'Run the CI gates as they run there: format, audit, coverage'
task :ci do
  sh 'bin/ci'
end

desc 'Run every quality gate (bin/ci)'
task check: :ci

task default: :check
