require "minitest/autorun"
require "tmpdir"
require "ship_android/decisions"

class DecisionsTest < Minitest::Test
  D = ShipAndroid::Decisions
  DRIFTWELL_KEYS = %w[storeFile storePassword keyAlias keyPassword].freeze
  RUCKPACE_KEYS = %w[RELEASE_STORE_FILE RELEASE_STORE_PASSWORD RELEASE_KEY_ALIAS RELEASE_KEY_PASSWORD].freeze

  def write(dir, name, text)
    File.join(dir, name).tap { |p| File.write(p, text) }
  end

  def test_read_properties_unescapes_and_skips_comments
    Dir.mktmpdir do |dir|
      path = write(dir, "local.properties", <<~PROPS)
        # comment
        sdk.dir=C\\:\\\\Users\\\\me\\\\Sdk

        keyAlias = driftwell-upload
      PROPS
      props = D.read_properties(path)
      assert_equal 'C:\\Users\\me\\Sdk', props["sdk.dir"]
      assert_equal "driftwell-upload", props["keyAlias"]
      assert_equal 2, props.size
    end
  end

  def test_read_properties_missing_file_is_empty
    assert_equal({}, D.read_properties("/no/such/file"))
  end

  def test_version_code_floor_reads_fallback
    text = 'versionCode = (project.findProperty("versionCode") as String?)?.toInt() ?: 3'
    assert_equal 3, D.version_code_floor(text)
  end

  def test_version_code_floor_raises_when_absent
    assert_raises(RuntimeError) { D.version_code_floor("versionCode = 3") }
  end

  # Kills: ignoring the floor (a burned-but-unlisted code gets reused).
  def test_next_version_code_respects_floor_when_play_is_empty
    assert_equal 3, D.next_version_code(play_codes: [], floor: 3)
  end

  # Kills: using only the internal track, or min instead of max.
  def test_next_version_code_is_max_plus_one_across_tracks
    assert_equal 8, D.next_version_code(play_codes: [3, 7, 5], floor: 3)
  end

  def test_next_version_code_floor_wins_over_lower_play_max
    assert_equal 10, D.next_version_code(play_codes: [4], floor: 10)
  end

  def test_release_notes_override_wins
    assert_equal "Fix GPS", D.release_notes(subjects: ["a"], override: "  Fix GPS ")
  end

  def test_release_notes_joins_subjects
    assert_equal "Fix A\nFix B", D.release_notes(subjects: ["Fix A", " ", "Fix B"], override: nil)
  end

  def test_release_notes_never_empty
    refute_empty D.release_notes(subjects: [], override: "")
  end

  # Kills: no truncation (Play rejects > 500 characters at upload, after a full build).
  def test_release_notes_truncated_to_limit_on_line_boundary
    subjects = Array.new(40) { |i| "Subject line number #{i} with some words" }
    notes = D.release_notes(subjects: subjects, override: nil)
    assert_operator notes.length, :<=, 500
    assert notes.end_with?("…")
    refute_includes notes, "Subject line number 39"
  end

  # Kills: a hardcoded key list - each app names its own four keys.
  def test_signing_problems_names_missing_keys_for_either_app
    assert_equal %w[storePassword keyAlias keyPassword],
                 D.signing_problems({ "storeFile" => "x.jks" }, DRIFTWELL_KEYS, "/tmp")
    assert_equal %w[RELEASE_STORE_PASSWORD RELEASE_KEY_ALIAS RELEASE_KEY_PASSWORD],
                 D.signing_problems({ "RELEASE_STORE_FILE" => "x.jks" }, RUCKPACE_KEYS, "/tmp")
  end

  def test_signing_problems_missing_store_file
    props = RUCKPACE_KEYS.to_h { |k| [k, "v"] }
    problems = D.signing_problems(props, RUCKPACE_KEYS, Dir.tmpdir)
    assert_equal 1, problems.size
    assert_match(/RELEASE_STORE_FILE/, problems.first)
  end

  # Kills: resolving the store file against the wrong directory. Driftwell's is relative to app/,
  # RuckPace's to the repo root; the caller passes the base.
  def test_signing_problems_resolves_store_file_against_the_given_base
    Dir.mktmpdir do |root|
      app = File.join(root, "app").tap { |d| Dir.mkdir(d) }
      write(app, "k.jks", "x")
      props = DRIFTWELL_KEYS.to_h { |k| [k, "v"] }.merge("storeFile" => "k.jks")
      assert_empty D.signing_problems(props, DRIFTWELL_KEYS, app)
      refute_empty D.signing_problems(props, DRIFTWELL_KEYS, root)
    end
  end

  def test_signing_problems_ok_with_absolute_store_file
    Dir.mktmpdir do |dir|
      store = write(dir, "k.jks", "x")
      props = DRIFTWELL_KEYS.to_h { |k| [k, "v"] }.merge("storeFile" => store)
      assert_empty D.signing_problems(props, DRIFTWELL_KEYS, Dir.tmpdir)
    end
  end

  def test_stamped_bundle_picks_the_one_carrying_the_code
    paths = ["/b/ruckpace-0.1.0-versionCode2.aab", "/b/ruckpace-0.1.0-versionCode3.aab"]
    assert_equal "/b/ruckpace-0.1.0-versionCode3.aab", D.stamped_bundle(paths, 3)
  end

  # Kills: uploading whatever stamped bundle is lying around - the 2026-09-14 stale-bundle upload.
  def test_stamped_bundle_raises_when_none_carries_the_code
    error = assert_raises(RuntimeError) { D.stamped_bundle(["/b/driftwell-0.2.0-versionCode2.aab"], 3) }
    assert_includes error.message, "versionCode3"
  end

  # Kills: a suffix/substring match - asking for 2 must not pick up versionCode12.
  def test_stamped_bundle_does_not_match_a_longer_code
    assert_raises(RuntimeError) { D.stamped_bundle(["/b/driftwell-0.2.0-versionCode12.aab"], 2) }
  end

  def test_stamped_bundle_raises_when_ambiguous
    paths = ["/b/driftwell-0.2.0-versionCode3.aab", "/b/driftwell-0.3.0-versionCode3.aab"]
    error = assert_raises(RuntimeError) { D.stamped_bundle(paths, 3) }
    assert_includes error.message, "driftwell-0.3.0-versionCode3.aab"
  end

  def test_version_code_reused_detection
    assert D.version_code_reused?("Google Api Error: forbidden: Version code 4 has already been used.")
    refute D.version_code_reused?("The caller does not have permission")
  end

  def test_tag_name
    assert_equal "testers/android/v4", D.tag_name(:android, 4)
  end

  # Ruby 3 passes `opts(dry_run: "x")` as keywords, not a positional hash, so gather both.
  def opts(options = nil, diagnostics_supported: true, **keywords)
    D.lane_options(options || keywords, diagnostics_supported: diagnostics_supported)
  end

  def test_lane_options_defaults
    assert_equal({ notes: nil, skip_tests: false, dry_run: false, diagnostics: false, allow_unmerged: false }, opts({}))
  end

  def test_lane_options_accepts_booleans_and_words
    o = opts(notes: "Fix GPS", skip_tests: true, dry_run: "YES", allow_unmerged: "yes")
    assert_equal({ notes: "Fix GPS", skip_tests: true, dry_run: true, diagnostics: false, allow_unmerged: true }, o)
    assert_equal false, opts(dry_run: "No")[:dry_run]
  end

  def test_lane_options_diagnostics_defaults_off_and_can_be_turned_on
    assert_equal true, opts(diagnostics: "yes")[:diagnostics]
    assert_raises(ArgumentError) { opts(diagnostics: "off") }
  end

  # Kills: RuckPace silently accepting diagnostics:true and building nothing different.
  def test_lane_options_rejects_diagnostics_when_the_app_has_none
    error = assert_raises(ArgumentError) { opts({ diagnostics: true }, diagnostics_supported: false) }
    assert_includes error.message, "diagnostics"
    assert_equal false, opts({}, diagnostics_supported: false)[:diagnostics]
  end

  # Kills: a typo'd key (dry-run, dryrun, allow-unmerged) silently ignored.
  def test_lane_options_rejects_unknown_keys
    %i[dry-run dryrun dry_run_ skip-tests note allow-unmerged unmerged].each do |key|
      error = assert_raises(ArgumentError) { opts(key => true) }
      assert_includes error.message, key.to_s
    end
  end

  def test_lane_options_rejects_bad_flag_values
    ["1", "0", "y", "", "truee", 1].each do |value|
      error = assert_raises(ArgumentError) { opts(dry_run: value) }
      assert_includes error.message, "dry_run"
    end
    assert_raises(ArgumentError) { opts(allow_unmerged: "1") }
  end

  def test_lane_options_rejects_non_text_notes
    assert_raises(ArgumentError) { opts(notes: true) }
  end

  def test_tag_message_round_trips
    assert_equal :off, D.tag_diagnostics(D.tag_message(diagnostics: false))
    assert_equal :on, D.tag_diagnostics(D.tag_message(diagnostics: true))
    assert_equal :none, D.tag_diagnostics(D.tag_message(diagnostics: nil))
    assert_nil D.tag_diagnostics("")
    assert_nil D.tag_diagnostics(nil)
  end

  def test_tag_message_records_unmerged_only_when_set
    assert D.tag_unmerged?(D.tag_message(diagnostics: false, unmerged: true))
    refute D.tag_unmerged?(D.tag_message(diagnostics: false))
    refute D.tag_unmerged?(nil)
  end

  def test_promote_options
    assert_equal({ version_code: 11, rollout: nil, dry_run: false, trust_untagged: false },
                 D.promote_options(version_code: "11"))
    assert_in_delta 0.2, D.promote_options(version_code: 11, rollout: "0.2")[:rollout]
    assert_nil D.promote_options(version_code: 11, rollout: "1")[:rollout]
  end

  def test_promote_options_rejects_bad_input
    [{}, { version_code: "v11" }, { version_code: "0" }, { version_code: "11", rollout: "20%" },
     { version_code: "11", rollout: "0" }, { version_code: "11", rollout: "1.5" },
     { version_code: "11", dryrun: true }, { version_code: "11", dry_run: "1" },
     { version_code: "11", allow_unmerged: true }].each do |o|
      assert_raises(ArgumentError, o.inspect) { D.promote_options(o) }
    end
  end

  def problem(**overrides)
    D.promotion_problem(**{ code: 12, internal_codes: [11, 12], tag_found: true,
                            tag_message: "diagnostics=off", trust_untagged: false,
                            diagnostics_supported: true }.merge(overrides))
  end

  def test_promotion_problem
    assert_nil problem
    assert_match(/not on the internal track/, problem(internal_codes: [11]))
    assert_match(/No tag/, problem(tag_found: false))
    assert_match(/diagnostics ON/, problem(tag_message: "diagnostics=on"))
    assert_match(/trust_untagged/, problem(tag_message: ""))
    assert_nil problem(tag_message: "", trust_untagged: true)
    assert_match(/diagnostics ON/, problem(tag_message: "diagnostics=on", trust_untagged: true))
  end

  # Kills: promoting an emergency build that skipped the merged/green gate.
  def test_promotion_problem_refuses_unmerged_builds
    assert_match(/allow_unmerged/, problem(tag_message: "diagnostics=off\nunmerged=true"))
    assert_match(/allow_unmerged/, problem(tag_message: "diagnostics=off\nunmerged=true", trust_untagged: true))
  end

  # Review Focus 4: RuckPace's lightweight pre-gem tags carry a commit message, not key=value lines.
  def test_promotion_problem_app_without_diagnostics
    assert_nil problem(diagnostics_supported: false, tag_message: "Fix the GPS drift on long rucks")
    assert_nil problem(diagnostics_supported: false, tag_message: "diagnostics=none")
    assert_match(/allow_unmerged/, problem(diagnostics_supported: false, tag_message: "diagnostics=none\nunmerged=true"))
  end
end
