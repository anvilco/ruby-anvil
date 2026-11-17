# frozen_string_literal: true

RSpec.describe Anvil::RateLimiter do
  def elapsed_ms
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - started
  end

  it "starts full" do
    limiter = described_class.new(tokens: 5, interval_ms: 1000)

    expect(limiter.tokens).to eq(5)
    expect(limiter.interval_ms).to eq(1000)
    expect(limiter.tokens_remaining).to be_within(0.01).of(5)
  end

  it "hands out its tokens without waiting" do
    limiter = described_class.new(tokens: 3, interval_ms: 10_000)

    spent = elapsed_ms { 3.times { limiter.remove_token } }

    expect(spent).to be < 50
    expect(limiter.tokens_remaining).to be < 1
  end

  it "makes the caller wait once the tokens are gone" do
    limiter = described_class.new(tokens: 2, interval_ms: 100)

    spent = elapsed_ms { 3.times { limiter.remove_token } }

    # The third token needs half an interval to refill
    expect(spent).to be >= 40
  end

  it "refills over the interval" do
    limiter = described_class.new(tokens: 10, interval_ms: 100)
    10.times { limiter.remove_token }

    sleep(0.05)

    expect(limiter.tokens_remaining).to be_within(2).of(5)
  end

  it "never refills past its capacity" do
    limiter = described_class.new(tokens: 2, interval_ms: 10)

    sleep(0.05)

    expect(limiter.tokens_remaining).to eq(2.0)
  end

  describe "#try_remove_tokens" do
    it "takes the tokens when they are all there" do
      limiter = described_class.new(tokens: 5, interval_ms: 10_000)

      expect(limiter.try_remove_tokens(3)).to be(true)
      expect(limiter.tokens_remaining).to be_within(0.01).of(2)
    end

    it "takes nothing when they are not" do
      limiter = described_class.new(tokens: 5, interval_ms: 10_000)

      expect(limiter.try_remove_tokens(6)).to be(false)
      expect(limiter.tokens_remaining).to be_within(0.01).of(5)
    end
  end

  describe "#tokens_in_use" do
    it "counts the tokens spent out of the bucket" do
      limiter = described_class.new(tokens: 5, interval_ms: 10_000)
      2.times { limiter.remove_token }

      expect(limiter.tokens_in_use).to eq(2)
    end

    it "is zero for an untouched bucket" do
      expect(described_class.new(tokens: 5, interval_ms: 10_000).tokens_in_use).to eq(0)
    end
  end

  it "is safe to share between threads" do
    limiter = described_class.new(tokens: 20, interval_ms: 50)

    threads = Array.new(4) { Thread.new { 5.times { limiter.remove_token } } }
    threads.each(&:join)

    expect(limiter.tokens_remaining).to be < 20
  end

  it "refuses a bucket that could never hand out a token" do
    expect do
      described_class.new(tokens: 0, interval_ms: 1000)
    end.to raise_error(ArgumentError, /tokens must be positive/)
    expect { described_class.new(tokens: 1, interval_ms: 0) }
      .to raise_error(ArgumentError, /interval_ms must be positive/)
  end
end
