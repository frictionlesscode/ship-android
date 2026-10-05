# Pure decisions behind the shared `testers` and `production` lanes. Kept free of fastlane and
# of I/O beyond reading a file it is handed, so every rule here is unit-tested; the Fastfile
# only wires these to git, gh, Gradle and Play. Merged on 2026-10-05 from Driftwell's and
# RuckPace's copies of ship_testers.rb (spec 2026-10-05-shared-ship-pipeline-design.md).
module ShipAndroid
  module Decisions
    TRACKS = %w[internal alpha beta production].freeze
    NOTES_LIMIT = 500 # Play's per-language release-notes limit

    module_function

    # The subset of java.util.Properties that local.properties uses: key=value lines,
    # # and ! comments, and backslash escapes (sdk.dir is written as C\:\\Users\\...).
    def read_properties(path)
      return {} unless File.exist?(path)

      File.readlines(path, chomp: true).each_with_object({}) do |raw, props|
        line = raw.strip
        next if line.empty? || line.start_with?("#", "!")

        key, value = line.split("=", 2)
        next if value.nil?

        props[key.strip] = value.strip.gsub(/\\(.)/, '\1')
      end
    end

    def version_code_floor(gradle_text)
      match = gradle_text.match(/findProperty\("versionCode"\).*?\?:\s*(\d+)/)
      raise "No versionCode fallback (`?: N`) found in app/build.gradle.kts" unless match

      match[1].to_i
    end

    # Play burns codes that no track reports (discarded drafts, rejected bundles), so the
    # gradle literal is a floor that records them.
    def next_version_code(play_codes:, floor:)
      [play_codes.max || 0, floor - 1].max + 1
    end

    def release_notes(subjects:, override:)
      text = override.to_s.strip
      text = subjects.map(&:strip).reject(&:empty?).join("\n") if text.empty?
      text = "Internal test build." if text.empty?
      truncate(text)
    end

    def truncate(text, limit = NOTES_LIMIT)
      return text if text.length <= limit

      cut = text[0, limit - 1]
      newline = cut.rindex("\n")
      cut = cut[0, newline] if newline && newline > limit / 2
      "#{cut.rstrip}…"
    end

    # keys are the app's four signing property names, store file first. Without all four and a
    # real store file, the release build fails (or silently skips) signing only after the whole
    # test run, so check up front. base_dir is what the store path is relative to: Driftwell's
    # Gradle resolves it with the app module's file(), RuckPace's with rootProject.file().
    def signing_problems(props, keys, base_dir)
      missing = keys.select { |k| props[k].to_s.strip.empty? }
      return missing unless missing.empty?

      store = File.expand_path(props[keys.first], base_dir)
      File.exist?(store) ? [] : ["#{keys.first} (no file at #{store})"]
    end

    # stampReleaseBundle copies each bundle to a name carrying its versionCode, because a stale
    # app-release.aab was once uploaded in place of the new one (Driftwell, 2026-09-14). Upload
    # only the copy for the code just built, and refuse to guess between two.
    def stamped_bundle(paths, code)
      suffix = "-versionCode#{code}.aab"
      matches = paths.select { |p| File.basename(p).end_with?(suffix) }
      raise "No stamped bundle ending #{suffix} among: #{paths.map { |p| File.basename(p) }.join(', ')}" if matches.empty?
      if matches.size > 1
        raise "More than one stamped bundle for versionCode#{code} - delete the stale one: " \
              "#{matches.map { |p| File.basename(p) }.join(', ')}"
      end

      matches.first
    end

    def version_code_reused?(message)
      message.to_s.match?(/version code.*already been used/i)
    end

    LANE_OPTIONS = %i[notes skip_tests dry_run diagnostics allow_unmerged].freeze
    FLAG_WORDS = { "true" => true, "yes" => true, "false" => false, "no" => false }.freeze

    # fastlane turns only true/yes (false/no) into booleans and passes any other key:value
    # through untouched, so `dry-run:true` or `dry_run:1` would otherwise read as "not a dry
    # run" and publish for real. Anything not understood exactly is an error.
    def lane_options(options, diagnostics_supported:)
      unknown = options.keys.map(&:to_sym) - LANE_OPTIONS
      unless unknown.empty?
        raise ArgumentError, "Unknown option(s): #{unknown.join(', ')} - expected only #{LANE_OPTIONS.join(', ')}"
      end

      opts = options.to_h { |k, v| [k.to_sym, v] }
      notes = opts[:notes]
      raise ArgumentError, "notes must be text, got #{notes.inspect}" unless notes.nil? || notes.is_a?(String)
      if !diagnostics_supported && !opts[:diagnostics].nil?
        raise ArgumentError, "diagnostics is not an option for this app - it has no diagnostics build"
      end

      {
        notes: notes,
        skip_tests: flag_value(:skip_tests, opts[:skip_tests]),
        dry_run: flag_value(:dry_run, opts[:dry_run]),
        # Off unless asked for: every internal build is then a production candidate.
        diagnostics: diagnostics_supported ? flag_value(:diagnostics, opts[:diagnostics]) : false,
        # The one bypass of the merged-and-green gate; recorded in the tag, refused by production.
        allow_unmerged: flag_value(:allow_unmerged, opts[:allow_unmerged]),
      }
    end

    def flag_value(name, value, default: false)
      return default if value.nil?
      return value if value == true || value == false

      word = FLAG_WORDS[value.to_s.downcase] if value.is_a?(String)
      raise ArgumentError, "#{name} must be true or false, got #{value.inspect}" if word.nil?

      word
    end

    def tag_name(platform, code)
      "testers/#{platform}/v#{code}"
    end

    # The upload tag is annotated with how the build was made, so promotion can check it rather
    # than trust memory: nothing in Play records it. diagnostics nil means the app has none.
    def tag_message(diagnostics:, unmerged: false)
      lines = ["diagnostics=#{diagnostics.nil? ? 'none' : (diagnostics ? 'on' : 'off')}"]
      lines << "unmerged=true" if unmerged
      lines.join("\n")
    end

    # :on, :off, :none, or nil when the tag says nothing (lightweight tags from before v12).
    def tag_diagnostics(message)
      word = message.to_s[/^diagnostics=(on|off|none)$/, 1]
      word&.to_sym
    end

    def tag_unmerged?(message)
      message.to_s.match?(/^unmerged=true$/)
    end

    PROMOTE_OPTIONS = %i[version_code rollout dry_run trust_untagged].freeze

    def promote_options(options)
      unknown = options.keys.map(&:to_sym) - PROMOTE_OPTIONS
      unless unknown.empty?
        raise ArgumentError, "Unknown option(s): #{unknown.join(', ')} - expected only #{PROMOTE_OPTIONS.join(', ')}"
      end

      opts = options.to_h { |k, v| [k.to_sym, v] }
      code = opts[:version_code].to_s
      raise ArgumentError, "version_code is required and must be a whole number, got #{opts[:version_code].inspect}" unless code.match?(/\A[1-9]\d*\z/)

      rollout = nil
      unless opts[:rollout].nil?
        text = opts[:rollout].to_s
        rollout = Float(text, exception: false) if text.match?(/\A0?\.\d+\z|\A1(\.0+)?\z/)
        raise ArgumentError, "rollout must be a fraction above 0 and at most 1 (e.g. 0.2), got #{opts[:rollout].inspect}" if rollout.nil? || rollout <= 0
        rollout = nil if rollout >= 1
      end

      {
        version_code: code.to_i,
        rollout: rollout,
        dry_run: flag_value(:dry_run, opts[:dry_run]),
        trust_untagged: flag_value(:trust_untagged, opts[:trust_untagged]),
      }
    end

    # Why this code must not be promoted, or nil if it may be. Only what internal testers have
    # already run goes to Production; never a build carrying tester tools or built unmerged.
    def promotion_problem(code:, internal_codes:, tag_found:, tag_message:, trust_untagged:, diagnostics_supported:)
      return "versionCode #{code} is not on the internal track (it has #{internal_codes.sort.join(', ')}) - ship and smoke-test it there first" unless internal_codes.include?(code)
      return "No tag #{tag_name(:android, code)} - cannot tell how versionCode #{code} was built" unless tag_found
      return "versionCode #{code} was built with allow_unmerged:true - merge the fix, ship from the default branch and promote that" if tag_unmerged?(tag_message)
      return nil unless diagnostics_supported

      case tag_diagnostics(tag_message)
      when :off then nil
      when :on then "versionCode #{code} was built with diagnostics ON (tester tools) - ship a diagnostics:false build and promote that"
      else
        return nil if trust_untagged

        "Tag #{tag_name(:android, code)} does not record diagnostics (built before tags did). " \
          "If you know it was a diagnostics:false build and Misc has no Diagnostics row, rerun with trust_untagged:true"
      end
    end
  end
end
