# frozen_string_literal: true

module Anvil
  # A token bucket that blocks callers until the next request is allowed.
  #
  # The bucket holds `tokens` and refills continuously over `interval_ms`, so a
  # client configured for 10 requests per second can burst 10 and then settles
  # into one request every 100ms. It is safe to share across threads.
  #
  # The client replaces its limiter with one built from the API's own
  # `x-ratelimit-limit` and `x-ratelimit-interval-ms` headers after the first
  # response, carrying over the tokens already spent. See {Client}.
  class RateLimiter
    # @return [Integer] how many tokens the bucket holds when full
    attr_reader :tokens
    # @return [Integer] how long a full refill takes, in milliseconds
    attr_reader :interval_ms

    # @param tokens [Integer] requests allowed per interval
    # @param interval_ms [Integer] the interval, in milliseconds
    def initialize(tokens:, interval_ms:)
      raise ArgumentError, "tokens must be positive" unless tokens.to_i.positive?
      raise ArgumentError, "interval_ms must be positive" unless interval_ms.to_i.positive?

      @tokens = tokens.to_i
      @interval_ms = interval_ms.to_i
      @available = @tokens.to_f
      @last_refill = now_ms
      @mutex = Mutex.new
    end

    # Takes one token, blocking until one is available.
    #
    # @return [Float] the tokens left after this one was taken
    def remove_token
      loop do
        wait_ms = nil

        @mutex.synchronize do
          refill
          if @available >= 1
            @available -= 1
            return @available
          end

          # How long until the bucket has refilled a whole token
          wait_ms = (1 - @available) * @interval_ms / @tokens
        end

        sleep_ms(wait_ms)
      end
    end

    # Takes tokens only if they are all available right now. Used when carrying
    # spent tokens over to a resized bucket.
    #
    # @param count [Integer]
    # @return [Boolean] whether the tokens were taken
    def try_remove_tokens(count)
      @mutex.synchronize do
        refill
        return false if @available < count

        @available -= count
        true
      end
    end

    # @return [Float] tokens available right now
    def tokens_remaining
      @mutex.synchronize do
        refill
        @available
      end
    end

    # @return [Integer] whole tokens spent out of this bucket, rounded up so a
    #   partially refilled bucket is treated as still spent
    def tokens_in_use
      [@tokens - tokens_remaining.floor, 0].max
    end

    private

    def refill
      current = now_ms
      elapsed = current - @last_refill
      @last_refill = current
      return if elapsed <= 0

      @available = [@tokens.to_f, @available + (elapsed * @tokens / @interval_ms)].min
    end

    def now_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

    # Separated so tests can run without really waiting.
    def sleep_ms(milliseconds)
      sleep(milliseconds / 1000.0)
    end
  end
end
