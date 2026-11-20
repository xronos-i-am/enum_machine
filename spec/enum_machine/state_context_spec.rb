# frozen_string_literal: true

RSpec.describe EnumMachine::StateContext do
  it "has an empty context outside a block" do
    expect(described_class.current).to eq({})
  end

  it "returns the context of the block" do
    described_class.with(order_id: 1) do
      expect(described_class.current).to eq order_id: 1
    end

    expect(described_class.current).to eq({})
  end

  it "replaces the context in a nested block and restores the outer one" do
    described_class.with(order_id: 1) do
      described_class.with(line_item_id: 2) do
        expect(described_class.current).to eq line_item_id: 2
      end

      expect(described_class.current).to eq order_id: 1
    end
  end

  it "restores the context when the block raises" do
    expect {
      described_class.with(source: :web) { raise "boom" }
    }.to raise_error("boom")

    expect(described_class.current).to eq({})
  end

  it "keeps contexts of different fibers apart" do
    described_class.with(source: :main) do
      expect(Fiber.new { described_class.current }.resume).to eq({})
    end
  end

  it "gives the block the same mutable hash callbacks write to" do
    described_class.with(order_id: 1) do |context|
      expect(context).to be described_class.current

      context[:dirty_order_id] = 1

      expect(described_class.current[:dirty_order_id]).to eq 1
    end
  end
end
