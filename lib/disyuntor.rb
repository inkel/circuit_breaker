require "micromachine"

class Disyuntor
  CircuitOpenError = Class.new(RuntimeError)

  attr_reader :failures, :opened_at, :threshold, :timeout

  def initialize(threshold: 5, timeout: 10, &block)
    @threshold = threshold
    @timeout   = timeout

    @on_circuit_open = if block_given?
                         block
                       else
                         Proc.new{ fail CircuitOpenError }
                       end

    close!
  end

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

  def on_circuit_open(&block)
    if block_given?
      @on_circuit_open = block
    else
      @on_circuit_open.(self)
    end
  end

  def close!     () states.trigger!(:reset) end
  def open!      () states.trigger!(:trip)  end
  def half_open! () states.trigger!(:try)   end

  def state      () states.state        end

  def closed?    () state == :closed    end
  def open?      () state == :open      end
  def half_open? () state == :half_open end

  def timed_out?
    open? && Time.now.to_i > (@opened_at + @timeout)
  end

  def try(&block)
    half_open! if timed_out?

    case
    when closed?    then on_circuit_closed(&block)
    when half_open? then on_circuit_half_open(&block)
    when open?      then on_circuit_open
    else
      fail RuntimeError, "Invalid state! #{state}"
    end
  end

  def on_circuit_closed(&block)
    block.call.tap { close! }
  rescue
    @failures += 1
    open! if @failures > @threshold
    raise
  end

  def on_circuit_half_open(&block)
    block.call.tap { close! }
  rescue
    open!
    raise
  end
end
