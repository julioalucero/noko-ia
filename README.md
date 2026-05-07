# noko-ia

Stats and automation tools for Noko time tracking with AI assistance.

## Setup

1. Copy `.env.sample` to `.env` and add your API keys:
   ```bash
   cp bin/.env.sample .env
   ```

2. Configure your Noko projects in `noko_projects.yml`

## Usage

### Generate daily stats

```bash
ruby bin/ia-noko-stats.rb MM-DD-YY TARGET_HOURS
```

Example:
```bash
ruby bin/ia-noko-stats.rb 05-06-26 7.5
```

This generates stats for the specified date with the target hours.

## Requirements

- Ruby
- Anthropic API key (for AI features)
