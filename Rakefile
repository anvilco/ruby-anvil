# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

desc "Run the integration test script against a real Anvil environment"
task :integration do
  ruby "test-client.rb"
end

namespace :types do
  desc "Regenerate lib/anvil/types/generated from the pinned @anvilco/types"
  task :generate do
    sh "npm run generate --prefix dev"
  end

  desc "Fail if lib/anvil/types/generated is out of step with the pinned @anvilco/types"
  task :check do
    sh "npm run check:generated --prefix dev"
  end
end

task default: %i[rubocop spec]
