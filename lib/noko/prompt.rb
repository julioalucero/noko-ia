module Noko
  # Builds the prompt sent to Claude from the day's timeline.
  class Prompt
    SOURCE_LABELS = {
      "git" => "[commit] ",
      "github" => "[github] ",
      "browser" => "[browser]"
    }.freeze

    def initialize(timeline:, target_minutes:, prefix_to_project:, date_label:)
      @timeline = timeline
      @target_minutes = target_minutes
      @prefix_to_project = prefix_to_project
      @date_label = date_label
    end

    def to_s
      <<~PROMPT
        You are helping log work hours into Noko time tracking for a software developer named Julio.

        Here is the activity for #{@date_label} (shell commands + git commits + GitHub activity + browser page visits):
        #{history_text}

        Total estimated active time: #{TimeFormat.format(@timeline.total_minutes)}
        Target workday: #{TimeFormat.format(@target_minutes)} total

        Known Noko project mappings (ticket prefix => project):
        #{projects_list}

        Here are real examples of how Julio logs time in Noko, so you can match his exact style:

        Examples:
        - 6:00 | Ombots | AUT-340 and AUT-339: Adding logging for manual roadmap
        - 4:00 | Ombots | AUT-341 Add logging to components/milestones/*
        - 0:30 | Operations | catch up with email and slack
        - 0:30 | Operations | #calls Standup
        - 1:00 | Fixers Guild | #calls Planning
        - 0:30 | Fixers Guild | Review Ays blog
        - 3:00 | Fixers Guild | AUT-324: Add roadmap generation tests
        - 0:30 | Fixers Guild | Review on AUT-344, AUT-343
        - 2:00 | Fixers Guild | AUT-324-add-git-roadmap-generation-tests

        Style rules:
        - Keep descriptions short and natural, like the examples above
        - Infer tickets from branch names (e.g. git checkout -b AUT-340-some-description => AUT-340)
        - Group same-ticket work into one entry when possible
        - If multiple tickets are related, combine them: "AUT-340 and AUT-339: description"
        - Tag calls with #calls at the start of the description
        - [github] lines are real actions Julio took (reviewed a PR, commented, opened a PR).
          These are authoritative — a review here is real review work worth logging.
        - [browser] lines are just pages Julio opened, and end with an engagement tag like
          [3x, 25min] = visits, time on page. Weight them by that: high visits/minutes means
          real work; a low tag (e.g. 1x, 3min) is likely just a page he glanced at — do NOT log
          a browser visit as work unless there is real activity (a [github]/[commit]/[shell] line)
          to back it up.
        - Ignore gaps > #{Timeline::MAX_GAP} minutes (lunch/breaks)
        - Total time should add up exactly to #{TimeFormat.format(@target_minutes)}
        - Always include an Operations entry of at least 0:30 for standup/email if there's no other operations activity

        Return a JSON object with an "entries" array. Each entry:
        - "time": H:MM format
        - "project": Noko project name from the mappings
        - "description": short natural description in Julio's style
      PROMPT
    end

    private

    def history_text
      @timeline.entries.map do |e|
        time = Time.at(e.ts).strftime("%H:%M")
        label = SOURCE_LABELS.fetch(e.source, "[shell]  ")
        "#{time}  #{label}  #{e.cmd}"
      end.join("\n")
    end

    def projects_list
      list = @prefix_to_project.map { |prefix, project| "#{prefix}-XXXX => #{project}" }.join("\n")
      list.empty? ? "(none configured)" : list
    end
  end
end
