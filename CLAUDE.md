# noko-ia

CLI that reconstructs a day of work from local activity and asks Claude to turn
it into Noko time-tracking entries. Run it, copy the output into Noko.

```bash
ruby bin/ia-noko-stats.rb              # today, 8h target
ruby bin/ia-noko-stats.rb 07-15-26 7.5 # specific day (MM-DD-YY), 7.5h target
```

Needs `ANTHROPIC_API_KEY` (loaded from `.env`, gitignored). `GITHUB_TOKEN` is
optional — without it the GitHub source is skipped.

## How it works

Three sources produce a shared `Entry {ts, cmd, source}`. They're merged into a
`Timeline`, rendered into a `Prompt`, sent to `Claude`, and printed by `Report`.
`Runner` orchestrates; `bin/` is just `Noko.run(ARGV)`.

```
bin/ia-noko-stats.rb        entrypoint (2 lines)
lib/noko.rb                 requires + ROOT + Noko.run
lib/noko/runner.rb          orchestration + arg parsing
lib/noko/config.rb          .env + noko_projects.yml
lib/noko/entry.rb           Entry = Struct(ts, cmd, source)
lib/noko/time_format.rb     H:MM <-> minutes (shared)
lib/noko/timeline.rb        merge/sort/dedup + total-active-time estimate
lib/noko/sources/shell.rb   ~/.zsh_history
lib/noko/sources/git.rb     commits from repos under ~/projects
lib/noko/sources/github.rb  GitHub events API (reviews/comments/PRs)
lib/noko/sources/browser.rb Brave history (dwell + glance filtering)
lib/noko/prompt.rb          builds the Claude prompt
lib/noko/claude.rb          API call + time balancing
lib/noko/report.rb          terminal output
```

## Key behavior

- **GitHub vs browser split**: the GitHub events API owns code/PR/review
  activity because it's authoritative — an event means you actually reviewed or
  commented, whereas a browser visit can't tell "reviewed" from "glanced". So
  `github.com` is intentionally NOT in `browser_domains`; the browser source
  covers Jira/docs/localhost only. Commits stay with the local git source
  (GitHub `PushEvent`s are skipped to avoid duplicating them).
- **Browser dwell/glance rule** (`sources/browser.rb`): pages are aggregated per
  title with a visit count and total dwell (time until the next visit to any
  page, capped at `DWELL_CAP` = 30 min). A page seen once for under `GLANCE_MIN`
  = 2 min is dropped as a glance. Kept pages carry a `[Nx, Mmin]` tag; the prompt
  tells Claude not to log a browser visit as work unless a github/commit/shell
  line backs it up (a lone visit can still slip through the mechanical filter).
- **SQLite quirks**: Brave locks its DB, so we query a `/tmp` copy. The empty
  string must be `''` (SQLite `""` is an identifier), so the query is fed over
  stdin — never through the shell.
- **Timeline** ignores gaps > `MAX_GAP` (90 min) as breaks, adds a 30 min tail
  buffer, then `Claude#balance` nudges the largest entry so times sum to target.
- **Config**: `noko_projects.yml` holds `projects` (ticket-prefix => Noko
  project) and `browser_domains` (host substrings counted as "work").

## Conventions

- Ruby, RuboCop defaults. Each source exposes `#entries` returning `Entry`s.
- Tests: RSpec. `bundle exec rspec`. Pure logic is covered (time_format,
  timeline, browser rules, claude balancing, prompt); the network call and DB
  read are not.
- Commit messages: imperative, one line, <=72 chars.
