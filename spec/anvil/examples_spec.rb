# frozen_string_literal: true

# dotnet-anvil's CI compiles its examples, so a renamed method breaks the build
# there. Rubocop only checks ours for syntax and style. This is the equivalent
# guard: everything the shipped samples call has to exist.
RSpec.describe "the shipped code samples" do
  def samples
    readme = File.read(File.expand_path("../../README.md", __dir__))
    blocks = readme.scan(/^```ruby\n(.*?)^```/m).flatten.map { |code| ["README.md", code] }
    blocks + Dir[File.expand_path("../../examples/*.rb", __dir__)].map { |f| [File.basename(f), File.read(f)] }
  end

  it "has samples to check" do
    expect(samples.length).to be >= 30
  end

  it "only calls client methods that exist" do
    missing = samples.flat_map do |name, code|
      code.scan(/\bclient\.([a-z_]+[?!]?)/).flatten.uniq
        .reject { |m| Anvil::Client.public_method_defined?(m) }
        .map { |m| "#{name}: client.#{m}" }
    end

    expect(missing).to be_empty
  end

  it "only names constants that exist" do
    missing = samples.flat_map do |name, code|
      code.scan(/\bAnvil::([A-Za-z][A-Za-z0-9:]*)/).flatten.uniq
        .reject { |path| Object.const_defined?("Anvil::#{path}") }
        .map { |path| "#{name}: Anvil::#{path}" }
    end

    expect(missing).to be_empty
  end

  it "only calls module methods that exist" do
    missing = samples.flat_map do |name, code|
      code.scan(/\bAnvil\.([a-z_]+)/).flatten.uniq
        .reject { |m| Anvil.respond_to?(m) }
        .map { |m| "#{name}: Anvil.#{m}" }
    end

    expect(missing).to be_empty
  end
end
