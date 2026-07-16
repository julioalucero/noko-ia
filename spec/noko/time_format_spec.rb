RSpec.describe Noko::TimeFormat do
  describe ".format" do
    it "formats whole hours" do
      expect(described_class.format(120)).to eq("2:00")
    end

    it "zero-pads the minutes" do
      expect(described_class.format(65)).to eq("1:05")
    end

    it "rounds fractional minutes" do
      expect(described_class.format(90.4)).to eq("1:30")
    end

    it "handles zero" do
      expect(described_class.format(0)).to eq("0:00")
    end
  end

  describe ".parse" do
    it "parses H:MM into minutes" do
      expect(described_class.parse("2:30")).to eq(150)
    end

    it "parses single-digit hours" do
      expect(described_class.parse("0:05")).to eq(5)
    end

    it "returns nil for minutes >= 60" do
      expect(described_class.parse("1:75")).to be_nil
    end

    it "returns nil for a malformed string" do
      expect(described_class.parse("2h30")).to be_nil
    end

    it "returns nil for a non-string" do
      expect(described_class.parse(150)).to be_nil
    end

    it "round-trips with .format" do
      expect(described_class.format(described_class.parse("7:45"))).to eq("7:45")
    end
  end
end
