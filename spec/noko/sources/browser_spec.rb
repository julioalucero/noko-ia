RSpec.describe Noko::Sources::Browser do
  subject(:browser) do
    described_class.new(day_start: 0, day_end: 86_400, domains: ["github.com"])
  end

  # Build a raw visit hash as produced by the SQLite parse step.
  def visit(ts, host, title)
    { ts: ts, host: host, title: title }
  end

  describe "#entries" do
    it "returns nothing when no work domains are configured" do
      no_domains = described_class.new(day_start: 0, day_end: 86_400, domains: [])
      expect(no_domains.entries).to eq([])
    end
  end

  describe "aggregation + glance filtering" do
    # Runs the private pipeline the way #entries does, minus the DB read.
    def entries_from(visits)
      browser.send(:aggregate, visits).filter_map { |t, p| browser.send(:to_entry, t, p) }
    end

    it "drops a page glanced once for a few seconds" do
      visits = [
        visit(0, "github.com", "colleague's PR"),
        visit(30, "x.com", "Twitter") # navigated away after 30s
      ]
      expect(entries_from(visits)).to be_empty
    end

    it "keeps a page with multiple visits and tags visits + minutes" do
      visits = [
        visit(0, "github.com", "MyPR"),
        visit(60, "x.com", "Twitter"),      # first view dwelled 60s
        visit(300, "github.com", "MyPR"),
        visit(360, "x.com", "Twitter")      # second view dwelled 60s
      ]
      entries = entries_from(visits)
      expect(entries.size).to eq(1)
      expect(entries.first.cmd).to eq("MyPR (github.com) [2x, 2min]")
      expect(entries.first.source).to eq("browser")
    end

    it "keeps a single visit with long dwell (a doc read once)" do
      visits = [
        visit(0, "github.com", "LongDoc"),
        visit(20 * 60, "x.com", "Twitter") # 20 min later
      ]
      entries = entries_from(visits)
      expect(entries.map(&:cmd)).to eq(["LongDoc (github.com) [1x, 20min]"])
    end

    it "caps dwell at DWELL_CAP for an idle tab" do
      visits = [
        visit(0, "github.com", "Idle"),
        visit(5 * 3600, "x.com", "Twitter") # 5h later, but capped
      ]
      mins = described_class::DWELL_CAP / 60
      expect(entries_from(visits).first.cmd).to eq("Idle (github.com) [1x, #{mins}min]")
    end

    it "places the entry at the first view's timestamp" do
      visits = [
        visit(500, "github.com", "MyPR"),
        visit(560, "x.com", "Twitter"),
        visit(100, "github.com", "MyPR"),  # earlier view, out of order
        visit(160, "x.com", "Twitter")
      ]
      expect(entries_from(visits).first.ts).to eq(100)
    end

    it "ignores pages that are not on a work domain" do
      visits = [
        visit(0, "x.com", "Twitter"),
        visit(60, "x.com", "Twitter"),
        visit(120, "youtube.com", "Video")
      ]
      expect(entries_from(visits)).to be_empty
    end
  end
end
