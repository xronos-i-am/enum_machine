# frozen_string_literal: true

RSpec.describe "DriverActiveRecord", :ar do
  let(:model) do
    Class.new(TestModel) do
      enum_machine :color, %w[red green blue]

      enum_machine :state, %w[created approved cancelled activated cancelled] do
        transitions(
          nil                    => "created",
          "created"              => [nil, "approved"],
          %w[cancelled approved] => "activated",
          "activated"            => %w[created cancelled],
        )
        aliases(
          "forming" => %w[created approved],
          "pending" => nil,
        )
        before_transition "created" => "approved" do |item|
          item.errors.add(:state, :invalid, message: "invalid transition") if item.color.red?
        end
        after_transition "created" => "approved" do |item|
          item.message = "after_approved"
        end
        after_transition %w[created] => %w[approved] do |item|
          item.color = "red"
        end
      end
    end
  end

  it "before_transition is runnable" do
    m = model.create(state: "created", color: "red")

    m.update(state: "approved")
    expect(m.errors.messages).to eq({ state: ["invalid transition"] })
  end

  it "after_transition is runnable" do
    m = model.create(state: "created", color: "green")

    m.state.to_approved!

    expect(m.message).to eq "after_approved"
    expect(m.color).to eq "red"

    m.reload

    expect(m.message).to be_nil
    expect(m.color).to eq "green"
  end

  it "check can_ methods" do
    m = model.new(state: "created", color: "red")
    expect(m.state.can?("approved")).to be true
    expect(m.state.can_approved?).to be true
    expect(m.state.can_cancelled?).to be false
    expect(m.state.can_activated?).to be false
  end

  it "check enum value comparsion" do
    m = model.new(state: "created", color: "red")

    expect(m.state).to eq "created"
    expect(m.state).to eq model::STATE::CREATED
    expect(model::STATE::CREATED).to eq "created"
    expect({ m.state => 1 }["created"]).to eq 1

    m.state = nil
    expect(m.state).to be_nil
  end

  it "possible_transitions returns next states" do
    expect(model.new(state: "created").state.possible_transitions).to eq [nil, "approved"]
    expect(model.new(state: "activated").state.possible_transitions).to eq %w[created cancelled]
  end

  it "raise when changed state is not defined in transitions" do
    m = model.create(state: "created")
    expect { m.update(state: "activated") }.to raise_error(EnumMachine::InvalidTransition) do |e|
      expect(e.message).to include('Transition "created" => "activated" not defined in enum_machine')
      expect(e.from).to eq "created"
      expect(e.to).to eq "activated"
      expect(e.enum_const.values).not_to be_empty
    end
  end

  it "test alias" do
    m = model.new(state: "created")

    expect(m.state.forming?).to be true
    expect(model::STATE.forming).to eq %w[created approved]
  end

  it "coerces states type" do
    state_enum = model.new(state: "created").state
    expect(model.new(message: state_enum).message).to eq "created"
  end

  context "when state is changed" do
    it "returns changed state string" do
      m = model.create(state: "created")
      state_was = m.state

      m.state = "approved"

      expect(m.state).to eq "approved"
      expect(state_was).to eq "created"
    end
  end

  context "when check skip transitions" do
    it "create record if transition is skipped" do
      m = model.new(state: "activated")

      m.skip_state_transitions { m.save! }

      expect(m.message).to be_nil

      expect { m.update(state: "approved") }.to raise_error(EnumMachine::InvalidTransition) do |e|
        expect(e.message).to include('Transition "activated" => "approved" not defined in enum_machine')
      end
    end

    it "checks skip context" do
      def a
        1
      end

      m = model.new(state: "activated")

      expect { m.skip_state_transitions { a + 1 } }
        .not_to raise_error
    end

    it "raise when simple create record" do
      expect { model.create(state: "activated") }.to raise_error(EnumMachine::InvalidTransition) do |e|
        expect(e.from).to be_nil
        expect(e.message).to include('Transition nil => "activated" not defined in enum_machine')
      end
    end
  end

  it "checks callbacks context" do
    semaphore =
      Class.new(TestModel) do
        enum_machine :color, %w[green orange red] do
          transitions(
            [nil, "red"] => "green",
            "green"      => "orange",
            "orange"     => "red",
          )
          before_transition "green" => "orange" do |item, from, to|
            item.message = "#{from} => #{to}"
          end
          before_transition "orange" => "red" do |item, _from, to|
            item.message = "#{item.color} => #{to}"
          end
          after_transition "red" => "green" do |item, _from, to|
            item.message = "#{item.color} => #{to}"
          end
        end
      end

    m = semaphore.create!(color: "green")

    expect { m.update!(color: "orange") }.to change(m, :message).to "green => orange"
    expect { m.update!(color: "red") }.to change(m, :message).to "orange => red"
    expect { m.update!(color: "green") }.to change(m, :message).to "green => green"
  end

  it "check error when empty transition" do
    expect {
      Class.new(TestModel) do
        enum_machine :state, %w[picked completed] do
          after_transition(nil => "picked") { 1 }
        end
      end
    }.to raise_error(EnumMachine::InvalidTransition) { |e|
      expect(e.from).to be_nil
      expect(e.message).to include('Transition nil => "picked" not defined in enum_machine')
    }
  end

  context "when transitions run inside a state context" do
    let(:context_model) do
      Class.new(TestModel) do
        enum_machine :state, %w[created approved cancelled] do
          transitions(
            nil        => "created",
            "created"  => %w[approved cancelled],
            "approved" => "cancelled",
          )
          before_transition "created" => "approved" do |item, _from, _to, context:|
            item.message = "before #{context[:action]}"
          end
          after_transition "created" => "approved" do |item, _from, _to, context:|
            item.params = "after #{context[:action]}"
          end
        end
      end
    end

    it "passes the context to before and after callbacks" do
      m = context_model.create!(state: "created")

      context_model.with_state_context(action: "approve") { m.update!(state: "approved") }

      expect(m.params).to eq "after approve"
      expect(m.reload.message).to eq "before approve"
    end

    it "passes an empty hash to callbacks outside a context block" do
      seen = :not_called
      model_without_context =
        Class.new(TestModel) do
          enum_machine :state, %w[created approved] do
            transitions nil => "created", "created" => "approved"
            before_transition("created" => "approved") { |_item, _from, _to, context:| seen = context }
          end
        end

      model_without_context.create!(state: "created").update!(state: "approved")

      expect(seen).to eq({})
    end

    it "replaces the context in a nested block and shows the outer one after it" do
      model_with_nested_context =
        Class.new(TestModel) do
          enum_machine :state, %w[created approved cancelled] do
            transitions nil => "created", "created" => "approved", "approved" => "cancelled"
            after_transition(any => any) { |item, _from, _to, context:| item.color = context[:marker] }
          end
        end

      m = model_with_nested_context.create!(state: "created")

      model_with_nested_context.with_state_context(marker: "outer", extra: true) do
        model_with_nested_context.with_state_context(marker: "inner") do
          expect(model_with_nested_context.state_context).to eq marker: "inner"

          m.update!(state: "approved")
        end
        expect(m.color).to eq "inner"
        expect(model_with_nested_context.state_context).to eq marker: "outer", extra: true

        m.update!(state: "cancelled")
        expect(m.color).to eq "outer"
      end

      expect(model_with_nested_context.state_context).to eq({})
    end

    it "passes the context for every way of changing the state" do
      model_with_any_transition =
        Class.new(TestModel) do
          enum_machine :state, %w[created approved cancelled] do
            transitions(
              nil         => "created",
              "created"   => %w[approved cancelled],
              "approved"  => "cancelled",
              "cancelled" => "approved",
            )
            before_transition(any => any) { |item, _from, _to, context:| item.message = context[:marker] }
          end
        end

      m = model_with_any_transition.create!(state: "created")

      model_with_any_transition.with_state_context(marker: "to_approved!") { m.state.to_approved! }
      expect(m.message).to eq "to_approved!"

      model_with_any_transition.with_state_context(marker: "update!") { m.update!(state: "cancelled") }
      expect(m.message).to eq "update!"

      model_with_any_transition.with_state_context(marker: "save!") do
        m.state = "approved"
        m.save!
      end
      expect(m.message).to eq "save!"
    end

    it "lets a callback mark the operation through the context hash" do
      model_with_marker =
        Class.new(TestModel) do
          enum_machine :state, %w[created approved] do
            transitions nil => "created", "created" => "approved"
            before_transition("created" => "approved") { |item, _from, _to, context:| context[:dirty_order_id] = item.id }
          end
        end

      marked = nil
      m = model_with_marker.create!(state: "created")

      model_with_marker.with_state_context(locked_order_id: 1) do |context|
        m.update!(state: "approved")
        marked = context[:dirty_order_id]
      end

      expect(marked).to eq m.id
    end

    it "lets a callback require a context key" do
      model_with_required_context =
        Class.new(TestModel) do
          enum_machine :state, %w[created approved] do
            transitions nil => "created", "created" => "approved"
            before_transition "created" => "approved" do |item, _from, _to, context:|
              raise EnumMachine::ContextRequiredError, "Order must be locked" unless context.key?(:locks)

              item.message = context.fetch(:locks)
            end
          end
        end

      m = model_with_required_context.create!(state: "created")

      expect { m.update!(state: "approved") }.to raise_error(EnumMachine::ContextRequiredError, "Order must be locked")

      model_with_required_context.with_state_context(locks: "3074665") { m.update!(state: "approved") }
      expect(m.reload.message).to eq "3074665"
    end
  end

  it "dup AR object not linked with original" do
    m = model.create(state: "created", color: "green")
    m.state # init parent
    m_dup = m.dup

    expect(m_dup.state.parent).to eq m_dup

    m_dup.skip_state_transitions { m_dup.state.to_approved! }

    expect(m.state).to eq "created"
    expect(m_dup.state).to eq "approved"
  end
end
