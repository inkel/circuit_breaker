require "micromachine"

class Disyuntor
  CircuitOpenError = Class.new(RuntimeError)

  attr_reader :failures, :threshold, :timeout

  def initialize(threshold:, timeout:)
    @threshold = threshold
    @timeout   = timeout

    on_circuit_open { fail CircuitOpenError }

    close!
  end

  def try(&block)
    half_open! if timed_out?

    case
    when closed?    then circuit_closed(&block)
    when half_open? then circuit_half_open(&block)
    when open?      then circuit_open
    end
  end

  def on_circuit_open(&block)
    raise ArgumentError, "Must pass a block" unless block_given?
    @on_circuit_open = block
  end

  def closed?    () states.state == :closed    end

  private

  attr_reader :opened_at

  def states
    @states ||= MicroMachine.new(:closed).tap do |fsm|
      fsm.when(:trip,  :half_open => :open,   :closed => :open)
      fsm.when(:reset, :half_open => :closed, :closed => :closed)
      fsm.when(:try,   :open      => :half_open)

      fsm.on(:open) do
        @opened_at = Time.now.to_i
      end

      fsm.on(:closed) do
        @opened_at = nil
        @failures  = 0
      end
    end
  end

  def close!     () states.trigger!(:reset) end
  def open!      () states.trigger!(:trip)  end
  def half_open! () states.trigger!(:try)   end

  def open?      () states.state == :open      end
  def half_open? () states.state == :half_open end

  def timed_out?
    open? && Time.now.to_i > next_timeout_at
  end

  def next_timeout_at
    opened_at + timeout
  end

  def increment_failures!
    @failures += 1
  end

  def circuit_closed(&block)
    ret = block.call
  rescue
    open! if increment_failures! >= threshold
    raise
  else
    close!
    ret
  end

  alias_method :circuit_half_open, :circuit_closed

  def circuit_open
    @on_circuit_open.call(self)
  end
end
