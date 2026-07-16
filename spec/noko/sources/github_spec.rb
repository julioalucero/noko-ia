RSpec.describe Noko::Sources::Github do
  subject(:github) { described_class.new(day_start: 0, day_end: 86_400, token: "t") }

  # Build a raw event as the API returns it.
  def event(type, number:, title:, repo: "ombulabs/blog", at: "1970-01-01T01:00:00Z")
    key = type.start_with?("Issue") ? "issue" : "pull_request"
    {
      "type" => type,
      "created_at" => at,
      "repo" => { "name" => repo },
      "payload" => { key => { "number" => number, "title" => title } }
    }
  end

  def aggregate(events)
    github.send(:aggregate, events)
  end

  describe "#entries" do
    it "returns nothing without a token" do
      no_token = described_class.new(day_start: 0, day_end: 86_400, token: "")
      expect(no_token.entries).to eq([])
    end
  end

  describe "aggregation" do
    it "turns a review event into a github entry" do
      events = [event("PullRequestReviewEvent", number: 554, title: "BLOG-554 Instrument LLM calls")]
      entry = aggregate(events).first
      expect(entry.source).to eq("github")
      expect(entry.cmd).to eq("github reviewed #554 BLOG-554 Instrument LLM calls (ombulabs/blog)")
    end

    it "collapses a review plus its inline comments into one entry" do
      events = [
        event("PullRequestReviewEvent", number: 554, title: "BLOG-554 X"),
        event("PullRequestReviewCommentEvent", number: 554, title: "BLOG-554 X"),
        event("PullRequestReviewCommentEvent", number: 554, title: "BLOG-554 X")
      ]
      expect(aggregate(events).size).to eq(1)
    end

    it "prefers 'reviewed' over 'commented on' when both happened on the same PR" do
      events = [
        event("IssueCommentEvent", number: 10, title: "FR-1 thing"),
        event("PullRequestReviewEvent", number: 10, title: "FR-1 thing")
      ]
      expect(aggregate(events).first.cmd).to include("github reviewed #10")
    end

    it "ignores events outside the day window" do
      events = [event("PullRequestReviewEvent", number: 1, title: "old", at: "1970-01-02T05:00:00Z")]
      expect(aggregate(events)).to be_empty
    end

    it "ignores event types that are not real activity" do
      events = [{ "type" => "WatchEvent", "created_at" => "1970-01-01T01:00:00Z",
                  "repo" => { "name" => "x/y" }, "payload" => {} }]
      expect(aggregate(events)).to be_empty
    end

    it "places the entry at the earliest activity timestamp" do
      events = [
        event("PullRequestReviewCommentEvent", number: 7, title: "t", at: "1970-01-01T05:00:00Z"),
        event("PullRequestReviewEvent", number: 7, title: "t", at: "1970-01-01T02:00:00Z")
      ]
      expect(aggregate(events).first.ts).to eq(Time.parse("1970-01-01T02:00:00Z").to_i)
    end
  end
end
