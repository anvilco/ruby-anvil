# frozen_string_literal: true

RSpec.describe Anvil::RateLimiter do
  def elapsed_ms
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - started
  end

  describe "the window" do
    it "lets the limit through without waiting" do
      limiter = described_class.new(limit: 3, interval_ms: 10_000)

      spent = elapsed_ms { 3.times { limiter.run { :ok } } }

      expect(spent).to be < 50
      expect(limiter.in_use).to eq(3)
    end

    it "makes the next caller wait for the oldest response to leave the window" do
      limiter = described_class.new(limit: 2, interval_ms: 100)
      2.times { limiter.run { :ok } }

      spent = elapsed_ms { limiter.run { :ok } }

      expect(spent).to be >= 50
    end

    it "stops counting a request once its interval has passed" do
      limiter = described_class.new(limit: 5, interval_ms: 50)
      5.times { limiter.run { :ok } }
      expect(limiter.in_use).to eq(5)

      sleep(0.15)

      expect(limiter.in_use).to eq(0)
    end

    it "counts a request that is still out, not just finished ones" do
      limiter = described_class.new(limit: 2, interval_ms: 10_000)
      seen = nil

      limiter.run { seen = limiter.in_use }

      expect(seen).to eq(1)
    end

    it "gives the slot back when the request raises" do
      limiter = described_class.new(limit: 1, interval_ms: 10_000)

      expect { limiter.run { raise Anvil::ConnectionError, "boom" } }.to raise_error(Anvil::ConnectionError)
      expect(limiter.in_use).to eq(1)
    end

    it "is safe to share between threads" do
      limiter = described_class.new(limit: 20, interval_ms: 50)
      counter = Queue.new

      threads = Array.new(4) { Thread.new { 5.times { limiter.run { counter << 1 } } } }
      threads.each(&:join)

      expect(counter.size).to eq(20)
    end
  end

  describe "a 429" do
    it "is retried for as long as the API keeps asking" do
      limiter = described_class.new(limit: 100, interval_ms: 1)
      allow(limiter).to receive(:sleep)
      refusals = 4
      attempts = 0

      result = limiter.run do
        attempts += 1
        raise Anvil::RateLimitError.new("limited", retry_after: 0.2, status_code: 429) if attempts <= refusals

        :finally
      end

      expect(result).to eq(:finally)
      expect(attempts).to eq(refusals + 1)
      expect(limiter).to have_received(:sleep).with(0.25).exactly(refusals).times
    end
  end

  describe ".retry_delay_seconds" do
    it "adds the buffer to what the API asked for" do
      expect(described_class.retry_delay_seconds("0.2")).to eq(0.25)
    end

    it "waits a second when the API named no delay" do
      expect(described_class.retry_delay_seconds(nil)).to eq(1.05)
    end

    it "waits a second when the delay is unreadable, such as an HTTP date" do
      expect(described_class.retry_delay_seconds("Wed, 21 Oct 2026 07:28:00 GMT")).to eq(1.05)
    end

    it "takes a negative delay as its own magnitude" do
      expect(described_class.retry_delay_seconds("-2")).to eq(2.05)
    end

    it "caps the wait at a minute, however long the API asks for" do
      expect(described_class.retry_delay_seconds("9999")).to eq(60.05)
    end
  end

  describe "#set_limits" do
    let(:limiter) { described_class.new(limit: 1, interval_ms: 1000) }

    it "replaces the limit and says it changed" do
      expect(limiter.set_limits(42, 4200)).to be(true)
      expect(limiter.limit).to eq(42)
      expect(limiter.interval_ms).to eq(4200)
    end

    it "does nothing when the limit is the same" do
      expect(limiter.set_limits(1, 1000)).to be(false)
    end

    it "ignores a limit that could never hand out a request" do
      expect(limiter.set_limits(0, 1000)).to be(false)
      expect(limiter.set_limits("not a number", 1000)).to be(false)
      expect(limiter.set_limits(5, nil)).to be(false)
      expect(limiter.limit).to eq(1)
    end
  end

  describe "#update_from_headers" do
    let(:limiter) { described_class.new(limit: 1, interval_ms: 1000) }

    it "adopts the organization's real limit" do
      limiter.update_from_headers("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "4200")

      expect(limiter.limit).to eq(42)
      expect(limiter.interval_ms).to eq(4200)
    end

    it "only does it once, however the later responses are headed" do
      limiter.update_from_headers("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "4200")
      limiter.update_from_headers("x-ratelimit-limit" => "7", "x-ratelimit-interval-ms" => "1000")

      expect(limiter.limit).to eq(42)
    end

    it "keeps what it has when the headers say nothing usable" do
      limiter.update_from_headers("x-ratelimit-limit" => "not a number", "x-ratelimit-interval-ms" => "0")

      expect(limiter.limit).to eq(1)
    end
  end

  describe ".shared" do
    it "hands the same limiter to the same environment and credentials" do
      one = described_class.shared(base_url: "https://staging.useanvil.com", auth_header: "Basic abc")
      two = described_class.shared(base_url: "https://staging.useanvil.com", auth_header: "Basic abc")

      expect(one).to be(two)
    end

    it "keeps different credentials and different environments apart" do
      one = described_class.shared(base_url: "https://staging.useanvil.com", auth_header: "Basic abc")

      expect(one).not_to be(described_class.shared(base_url: "https://staging.useanvil.com", auth_header: "Basic zzz"))
      expect(one).not_to be(described_class.shared(base_url: "https://app.useanvil.com", auth_header: "Basic abc"))
    end
  end
end
