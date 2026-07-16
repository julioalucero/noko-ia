RSpec.describe Noko::Prompt do
  subject(:prompt) do
    described_class.new(
      timeline: timeline,
      target_minutes: 480,
      prefix_to_project: { "AUT" => "Ombots" },
      date_label: "July 15, 2026"
    ).to_s
  end

  let(:timeline) do
    Noko::Timeline.new([
      Noko::Entry.new(ts: Time.mktime(2026, 7, 15, 9, 0, 0).to_i, cmd: "git commit [AUT-1] fix", source: "git"),
      Noko::Entry.new(ts: Time.mktime(2026, 7, 15, 9, 30, 0).to_i, cmd: "MyPR (github.com) [3x, 25min]", source: "browser")
    ])
  end

  it "labels each source" do
    expect(prompt).to include("[commit]", "[browser]")
  end

  it "renders the entry commands with their times" do
    expect(prompt).to include("09:00")
    expect(prompt).to include("MyPR (github.com) [3x, 25min]")
  end

  it "lists the project mappings" do
    expect(prompt).to include("AUT-XXXX => Ombots")
  end

  it "shows the target workday" do
    expect(prompt).to include("Target workday: 8:00 total")
  end

  it "explains the engagement tag so glances are not logged" do
    expect(prompt).to include("engagement tag")
  end

  context "with no project mappings" do
    let(:timeline) { Noko::Timeline.new([Noko::Entry.new(ts: 0, cmd: "x", source: "shell")]) }

    subject(:prompt) do
      described_class.new(
        timeline: timeline, target_minutes: 480,
        prefix_to_project: {}, date_label: "July 15, 2026"
      ).to_s
    end

    it "says none are configured" do
      expect(prompt).to include("(none configured)")
    end
  end
end
