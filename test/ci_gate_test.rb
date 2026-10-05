require "minitest/autorun"
require "ship_android/ci_gate"

class CiGateTest < Minitest::Test
  G = ShipAndroid::CiGate

  def run_(name, status: "completed", conclusion: "success", id: 1)
    { "id" => id, "name" => name, "status" => status, "conclusion" => conclusion,
      "html_url" => "https://github.com/o/r/runs/#{id}" }
  end

  def test_ci_problem_all_green
    assert_nil G.ci_problem([run_("build"), run_("ios", id: 2)])
  end

  # Kills: an empty list reading as "nothing failed" - a disabled workflow would ship.
  def test_ci_problem_no_checks_is_a_refusal
    assert_match(/No CI checks/, G.ci_problem([]))
  end

  def test_ci_problem_names_pending_checks
    msg = G.ci_problem([run_("build"), run_("ios", status: "in_progress", conclusion: nil, id: 2)])
    assert_match(/still running/, msg)
    assert_includes msg, "ios"
    refute_includes msg, "build"
  end

  def test_ci_problem_names_failures_with_links
    msg = G.ci_problem([run_("build", conclusion: "failure", id: 7), run_("ios", id: 8)])
    assert_match(/not green/, msg)
    assert_includes msg, "build"
    assert_includes msg, "runs/7"
  end

  # RuckPace's record-screenshots job is skipped on every push by design.
  def test_ci_problem_allows_skipped_and_neutral
    assert_nil G.ci_problem([run_("build"), run_("record-screenshots", conclusion: "skipped", id: 2),
                             run_("lint", conclusion: "neutral", id: 3)])
  end

  def test_ci_problem_cancelled_is_not_green
    assert_match(/not green/, G.ci_problem([run_("build", conclusion: "cancelled")]))
  end

  # Review Focus 2: a re-run replaces the failure it re-ran.
  def test_ci_problem_rerun_replaces_failure
    assert_nil G.ci_problem([run_("build", conclusion: "failure", id: 5), run_("build", id: 9)])
    assert_match(/not green/, G.ci_problem([run_("build", id: 5), run_("build", conclusion: "failure", id: 9)]))
  end

  def test_branch_problem_at_tip
    assert_nil G.branch_problem(head: "a" * 40, tip: "a" * 40, branch: "main", current_branch: "main")
  end

  def test_branch_problem_on_a_feature_branch
    msg = G.branch_problem(head: "a" * 40, tip: "b" * 40, branch: "main", current_branch: "feat/x")
    assert_includes msg, "feat/x"
    assert_includes msg, "allow_unmerged"
  end

  # Review Focus 1: committed locally but never pushed, so CI never saw it.
  def test_branch_problem_local_commit_not_pushed
    msg = G.branch_problem(head: "a" * 40, tip: "b" * 40, branch: "main", current_branch: "main")
    assert_includes msg, "origin/main"
    assert_includes msg, "aaaaaaaaa"
  end

  # Review Focus 3: checked out at a tag or SHA.
  def test_branch_problem_detached_head
    msg = G.branch_problem(head: "a" * 40, tip: "b" * 40, branch: "master", current_branch: "HEAD")
    assert_includes msg, "detached"
    assert_includes msg, "master"
  end
end
