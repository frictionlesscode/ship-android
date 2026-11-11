# ship-android

Shared release tooling for frictionlesscode's Android apps (Driftwell, RuckPace). One repo, two
things versioned together:

- **A Ruby gem, `ship_android`.** It holds the fastlane `testers` and `production` lanes, their
  pure rules (`lib/ship_android/decisions.rb`, `ci_gate.rb`), and `ShipAndroid.configure`.
- **A Claude Code plugin.** It carries the `/ship-testers` and `/ship-production` skills that
  drive those lanes. It is listed in the `frictionlesscode/claude-plugins` marketplace:
  `/plugin install ship-android@frictionlesscode`.

The lanes ship only **merged and green** commits:

- `testers` refuses unless HEAD is the tip of the default branch on origin and every CI check
  on it passed. No checks at all is also a refusal.
- `production` refuses a tagged commit that isn't on the default branch or isn't green.
- `allow_unmerged:true` is the one emergency bypass. The tag records it, and production refuses
  that build.

Design: `docs/superpowers/specs/2026-10-05-shared-ship-pipeline-design.md` in the Driftwell repo.

## Using it from an app

`Gemfile`:

```ruby
gem "fastlane", "~> 2.228"
gem "ship_android", git: "https://github.com/frictionlesscode/ship-android.git", tag: "v1.0.0"
```

`fastlane/Fastfile`:

```ruby
require "ship_android"
ShipAndroid.configure(root: File.expand_path("..", __dir__), ...)
import ShipAndroid::FASTFILE
```

Run lanes as `bundle exec ruby -S fastlane android testers ...`, never through `fastlane.bat`,
which cuts multi-line arguments.

## Configuration keys

| Key | Required | Meaning | Driftwell | RuckPace |
|---|---|---|---|---|
| `root` | yes | Repo root | `File.expand_path("..", __dir__)` | same |
| `package` | yes | Play package name | `com.pathtotrueyou.driftwell` | `com.pathtotrueyou.ruckpace` |
| `signing_file` | yes | Properties file holding the four signing keys | `app/keystore.properties` | `local.properties` |
| `signing_keys` | yes | The four key names, **store file first** | `storeFile storePassword keyAlias keyPassword` | `RELEASE_STORE_FILE ...` |
| `store_file_base` | yes | Directory the store path is relative to | `app` | `.` |
| `test_tasks` | yes | Gradle tasks the lane runs before building | `testDebugUnitTest :shared:testAndroidHostTest` | `testDebugUnitTest` |
| `setup_doc` | yes | Doc named in error messages | `docs/PLAY-INTERNAL-SETUP.md` | `docs/releasing.md` |
| `diagnostics_property` | no | Gradle property for a tester-tools build; `nil` means none, and the lane rejects `diagnostics:` | `diagnosticsEnabled` | `nil` |
| `preflight` | no | `lambda { \|root\| }` returning an error message or `nil` | checks the sherpa-onnx AAR | `nil` |

Every app also needs:

- `PLAY_SERVICE_ACCOUNT_JSON` in `local.properties`;
- a `versionCode = (findProperty("versionCode") ...) ?: N` floor in `app/build.gradle.kts`;
- a `stampReleaseBundle` Gradle task that copies the release bundle to
  `app/build/outputs/upload/<name>-versionCode<N>.aab`.

## Tests

```bash
export PATH="/c/Ruby33-x64/bin:$PATH"
ruby -Ilib -Itest -e 'ARGV.each { |f| require File.expand_path(f) }' test/*_test.rb
```

The lanes themselves have no unit tests: they call git, gh, Gradle and Play. Prove a lane change
with `dry_run:true` in an app, which runs every gate and has Play validate without publishing.

## Releasing a new version

1. Bump `version` in `ship_android.gemspec` and `.claude-plugin/plugin.json`.
2. Commit, then `git tag -a vX.Y.Z -m vX.Y.Z && git push origin main vX.Y.Z`.
3. In each app: bump the `tag:` in its `Gemfile`, run `bundle update ship_android`, and open a PR.
4. Refresh the plugin: `/plugin marketplace update frictionlesscode`.

## Adding a third app

1. Copy an app's `fastlane/Fastfile` and change its config.
2. Add the `Gemfile` line and the `stampReleaseBundle` task. Copy it from RuckPace's
   `app/build.gradle.kts`.
3. Give the repo CI on a self-hosted runner and protect its default branch, requiring its checks.

## License

MIT. See [LICENSE](LICENSE).
