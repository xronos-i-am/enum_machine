# frozen_string_literal: true

module EnumMachine
  # Fiber-local hash of the current operation context.
  #
  #   LineItem.with_state_context(locked_order_id: 3074665) do |context|
  #     line_item.state.to_absent!
  #
  #     order.recalculate! if context[:dirty_order_id]
  #   end
  #
  # Transition callbacks receive the same hash and may write to it:
  #
  #   before_transition "booked" => "absent" do |item, _from, _to, context:|
  #     raise EnumMachine::ContextRequiredError unless context.fetch(:locked_order_id) == item.order_id
  #   end
  #
  #   after_transition "booked" => "absent" do |item, _from, _to, context:|
  #     context[:dirty_order_id] = item.order_id
  #   end
  #
  # There is one context per operation: a block sets it for its scope and the previous
  # value is restored on exit. The hash is fiber-local, so a new fiber starts without one.
  module StateContext
    KEY = :__enum_machine_state_context
    EMPTY = {}.freeze

    # Methods added to a class with a state machine: `LineItem.with_state_context(...) { ... }`
    module ClassMethods
      def with_state_context(context = {}, &block)
        StateContext.with(context, &block)
      end

      # Context of the current operation, `{}` outside of it.
      def state_context
        StateContext.current
      end
    end

    def self.current
      Thread.current[KEY] || EMPTY
    end

    def self.with(context)
      previous = Thread.current[KEY]
      Thread.current[KEY] = context
      yield context
    ensure
      Thread.current[KEY] = previous
    end
  end
end
