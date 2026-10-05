# Pure rules for "merged and green": the commit being shipped must be the tip of the default
# branch on origin, and every CI check on it must have passed. The Fastfile fetches the inputs
# (git, `gh api .../check-runs`); everything decided from them is here and unit-tested.
module ShipAndroid
  module CiGate
    PASSING = %w[success neutral skipped].freeze

    module_function

    # A job re-run adds a new check run under the same name; only the latest one counts.
    def latest_runs(runs)
      runs.group_by { |r| r["name"] }.map { |_, rs| rs.max_by { |r| r["id"].to_i } }
    end

    def ci_problem(runs)
      return "No CI checks reported on this commit - is the workflow disabled or broken? Nothing ships without CI." if runs.empty?

      latest = latest_runs(runs)
      pending = latest.reject { |r| r["status"] == "completed" }
      unless pending.empty?
        return "CI still running on this commit: #{pending.map { |r| "#{r['name']} (#{r['status']})" }.join(', ')} - " \
               "rerun once it is green (a queued job may mean its runner's machine is asleep)"
      end

      failed = latest.reject { |r| PASSING.include?(r["conclusion"]) }
      return nil if failed.empty?

      "CI is not green on this commit: #{failed.map { |r| "#{r['name']} (#{r['conclusion']}) #{r['html_url']}" }.join('; ')}"
    end

    def branch_problem(head:, tip:, branch:, current_branch:)
      return nil if head == tip

      short = head[0, 9]
      if current_branch == "HEAD"
        "HEAD is detached at #{short}, not the tip of origin/#{branch} - check out #{branch} and pull, " \
          "or pass allow_unmerged:true for an emergency build"
      elsif current_branch != branch
        "HEAD is on #{current_branch}, not #{branch} - merge it first, or pass allow_unmerged:true for an emergency build"
      else
        "#{branch} at #{short} is not the tip of origin/#{branch} (#{tip[0, 9]}) - pull, or push and let CI run"
      end
    end
  end
end
