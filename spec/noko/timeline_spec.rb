RSpec.describe Noko::Timeline do
  def entry(ts, cmd: "x", source: "shell")
    Noko::Entry.new(ts: ts, cmd: cmd, source: source)
  end

  describe "#empty?" do
    it "is true with no entries" do
      expect(described_class.new([])).to be_empty
    end

    it "is false with entries" do
      expect(described_class.new([entry(0)])).not_to be_empty
    end
  end

  describe "#entries" do
    it "sorts entries by timestamp" do
      timeline = described_class.new([entry(300), entry(100), entry(200)])
      expect(timeline.entries.map(&:ts)).to eq([100, 200, 300])
    end

    it "drops entries sharing a timestamp" do
      timeline = described_class.new([entry(100, cmd: "a"), entry(100, cmd: "b")])
      expect(timeline.entries.size).to eq(1)
    end
  end

  describe "#total_minutes" do
    it "sums the gaps plus the tail buffer" do
      # 10 min + 10 min of gaps, then a 30 min tail buffer
      timeline = described_class.new([entry(0), entry(600), entry(1200)])
      expect(timeline.total_minutes).to eq(20 + Noko::Timeline::TAIL_BUFFER)
    end

    it "ignores gaps larger than MAX_GAP" do
      # 3h apart => gap ignored, only the tail buffer remains
      timeline = described_class.new([entry(0), entry(3 * 3600)])
      expect(timeline.total_minutes).to eq(Noko::Timeline::TAIL_BUFFER)
    end

    it "counts a gap exactly at MAX_GAP" do
      timeline = described_class.new([entry(0), entry(Noko::Timeline::MAX_GAP * 60)])
      expect(timeline.total_minutes).to eq(Noko::Timeline::MAX_GAP + Noko::Timeline::TAIL_BUFFER)
    end
  end
end
