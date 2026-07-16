RSpec.describe Noko::Claude do
  subject(:client) { described_class.new("test-key") }

  # #balance is the pure part worth testing (no network).
  def balance(entries, target)
    client.send(:balance, entries, target)
  end

  def entry(time, project: "Ombots", description: "work")
    { "time" => time, "project" => project, "description" => description }
  end

  it "leaves entries untouched when they already hit the target" do
    entries = [entry("4:00"), entry("4:00")]
    expect(balance(entries, 480).map { |e| e["time"] }).to eq(["4:00", "4:00"])
  end

  it "adds the missing time to the largest entry" do
    entries = [entry("2:00"), entry("1:00")]
    result = balance(entries, 480) # need +5h; goes onto the 2:00 entry
    expect(result[0]["time"]).to eq("7:00")
    expect(result[1]["time"]).to eq("1:00")
  end

  it "trims the largest entry when over target" do
    entries = [entry("5:00"), entry("1:00")]
    result = balance(entries, 300) # 5h target, currently 6h
    expect(result[0]["time"]).to eq("4:00")
  end

  it "creates an Operations entry when there are no entries" do
    result = balance([], 480)
    expect(result).to eq([
      { "time" => "8:00", "project" => "Operations", "description" => "General admin" }
    ])
  end
end
