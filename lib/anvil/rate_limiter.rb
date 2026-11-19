# frozen_string_literal: true

require "digest"
require "monitor"

module Anvil
  # Keeps requests inside the API's rate limit, and retries the ones it still
  # refuses.
  #
  # A request takes a slot before it is sent and gives it back when its response
  # arrives, so the requests in flight count against the limit alongside the ones
  # that have already finished. A finished request keeps counting for one
  # interval, which is what makes this a sliding window rather than a bucket that
  # refills on a fixed tick.
  #
  # The limiter is shared per process, keyed by the environment and the
  # credentials, so several clients built against the same organization throttle
  # as one. See {.shared}.
  #
  # The algorithm is python-anvil's `rate_limit.py`, which the SDK conventions
  # name as the reference for transport.
  class RateLimiter
    include MonitorMixin

    # Added to the window and to every retry delay, so the API's clock and this
    # one ticking apart cannot push a request over the line.
    RETRY_BUFFER_MS = 50

    # What to wait when a 429 names no delay. Retrying after only the buffer
    # would hammer a server that is already refusing.
    DEFAULT_RETRY_AFTER_MS = 1000

    # However long a 429 asks for, wait no longer than this.
    MAX_RETRY_AFTER_MS = 60_000

    # @return [Integer] requests allowed per interval
    attr_reader :limit
    # @return [Integer] the interval, in milliseconds
    attr_reader :interval_ms

    # @param limit [Integer] requests allowed per interval
    # @param interval_ms [Integer] the interval, in milliseconds
    def initialize(limit:, interval_ms:)
      super()
      @limit = positive_int(limit) || 1
      @interval_ms = positive_int(interval_ms) || 1000
      @in_flight = 0
      @finished_at = []
      @has_set_from_response = false
      @setting_in_progress = false
      @gate_open = false
      @turn = new_cond
    end

    # The limiter every client with these credentials shares.
    #
    # @param base_url [String]
    # @param auth_header [String]
    # @param limit [Integer]
    # @param interval_ms [Integer]
    # @return [RateLimiter]
    def self.shared(base_url:, auth_header:, limit: 1, interval_ms: 1000)
      key = [base_url, Digest::SHA256.hexdigest(auth_header.to_s)]
      registry_lock.synchronize do
        registry[key] ||= new(limit: limit, interval_ms: interval_ms)
      end
    end

    # @api private
    def self.registry
      @registry ||= {}
    end

    # @api private
    def self.registry_lock
      @registry_lock ||= Mutex.new
    end

    # How long to wait before retrying a 429: the seconds it asked for, capped,
    # plus the buffer. A missing or unreadable value means one second.
    #
    # @param retry_after [String, Numeric, nil] the Retry-After header
    # @return [Float] seconds
    def self.retry_delay_seconds(retry_after)
      asked = begin
        seconds = Float(retry_after).abs
        seconds.finite? ? seconds : DEFAULT_RETRY_AFTER_MS / 1000.0
      rescue ArgumentError, TypeError
        DEFAULT_RETRY_AFTER_MS / 1000.0
      end

      [asked, MAX_RETRY_AFTER_MS / 1000.0].min + (RETRY_BUFFER_MS / 1000.0)
    end

    # Replaces the limit, keeping the requests already counted.
    #
    # @return [Boolean] whether anything changed
    # rubocop:disable-next Naming/PredicateMethod -- it sets the limits and reports whether they moved
    def set_limits(limit, interval_ms)
      limit = positive_int(limit)
      interval_ms = positive_int(interval_ms)
      return false unless limit && interval_ms
      return false if limit == @limit && interval_ms == @interval_ms

      synchronize do
        @limit = limit
        @interval_ms = interval_ms
        @turn.broadcast
      end
      true
    end

    # Adopts the organization's real limit from a response, once.
    #
    # @param headers [Hash{String => String}] keys downcased
    # @return [void]
    def update_from_headers(headers)
      return if @has_set_from_response

      set_limits(headers["x-ratelimit-limit"], headers["x-ratelimit-interval-ms"])
      synchronize do
        @has_set_from_response = true
        release_setup_gate
      end
    end

    # Runs the block when the limit allows, retrying it after any 429.
    #
    # The block is called again for each retry, so it has to be able to build
    # its request again.
    #
    # @yieldreturn [Object]
    # @return [Object] whatever the block returned
    def run
      loop do
        acquired = false
        begin
          wait_for_turn
          acquired = true
          result = yield
        rescue RateLimitError => e
          finish if acquired
          release_setup_gate
          sleep(self.class.retry_delay_seconds(e.retry_after))
          next
        rescue Exception # rubocop:disable Lint/RescueException -- the request may have reached the API, so the slot has to be given back whatever happened
          finish if acquired
          release_setup_gate
          raise
        end
        finish
        # The first response is in, with or without limit headers: let the requests
        # held behind it go, or a response missing them would hold them forever
        release_setup_gate
        return result
      end
    end

    # @return [Integer] requests counting against the limit right now
    def in_use
      synchronize do
        prune(monotonic_now)
        @in_flight + @finished_at.length
      end
    end

    private

    # Waits until another request would stay within `limit` requests in any
    # `interval_ms`: the ones out now, plus those whose response arrived inside
    # the last interval.
    def wait_for_turn
      synchronize do
        # Until the first response has arrived, only the request whose response
        # it will be may go
        @turn.wait_while { @setting_in_progress && !@gate_open }
        @setting_in_progress = true unless @gate_open

        loop do
          now = monotonic_now
          window_start = prune(now)

          if @in_flight + @finished_at.length < @limit
            @in_flight += 1
            return
          end

          if @finished_at.empty?
            # Every slot is a request still out; a response will wake us
            @turn.wait
          else
            @turn.wait(@finished_at.first - window_start)
          end
        end
      end
    end

    # A response arrived, or the request failed: it counts for another interval.
    def finish
      synchronize do
        @in_flight -= 1
        @finished_at << monotonic_now
        @turn.broadcast
      end
    end

    # Lets the requests waiting on the first response go ahead.
    def release_setup_gate
      synchronize do
        @gate_open = true
        @setting_in_progress = false
        @turn.broadcast
      end
    end

    # Drops the responses that have left the window. The buffer allows for the
    # API's clock and this one ticking apart.
    def prune(now)
      window_start = now - ((@interval_ms + RETRY_BUFFER_MS) / 1000.0)
      @finished_at.shift while @finished_at.first && @finished_at.first <= window_start
      window_start
    end

    # Not the wall clock, so a change to it cannot hold requests up.
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def positive_int(value)
      number = Integer(value)
      number.positive? ? number : nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
