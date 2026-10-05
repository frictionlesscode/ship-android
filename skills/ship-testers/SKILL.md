---
name: ship-testers
description: Ship the current commit of an Android app that uses ship_android (Driftwell, RuckPace) to its Google Play internal testing track so testers can update. Use when the developer says ship/push/release to testers, internal track, or "get this fix to testers". Args - notes:'...', skip_tests:true, dry_run:true, diagnostics:true (apps with a diagnostics build only), allow_unmerged:true (emergency only).
---

# Ship to testers

Runs `fastlane android testers` from the shared `ship_android` gem. The app's own
`fastlane/Fastfile` holds its config: read the `package:` line there to name the app.

The order of operations is **merge, CI green, then ship**. The lane refuses anything else
unless `allow_unmerged:true` is passed.

1. **Preflight, read-only.**
   - Run `git status --porcelain`. If it isn't empty, stop and show what's dirty. Never commit
     or stash on the developer's behalf.
   - Run `git rev-parse --abbrev-ref HEAD` and `gh repo view --json defaultBranchRef`. If HEAD
     isn't the default branch, say the lane will refuse and that the fix is to merge the PR
     first. Only mention `allow_unmerged:true` if the developer calls it an emergency.
2. **Confirm unless dry_run.** An upload reaches real testers' phones. Show:
   - the app, the branch, and the short SHA and subject of HEAD;
   - whether tests will run;
   - the release notes testers will see: the developer's `notes:` if given, otherwise preview
     them with `git describe --tags --abbrev=0 --match 'testers/android/v*'` and
     `git log --format=%s <tag>..HEAD` (or `-n 10` without a tag). The lane truncates notes to
     500 characters.

   Then ask. Skip only if the developer already said to ship without asking in this conversation.
3. **Run** from the repo root, in the background (tests plus a release build take 3-10+ minutes):
   `export PATH="/c/Ruby33-x64/bin:$PATH" && bundle exec ruby -S fastlane android testers` plus args.
   - **Keep the `ruby -S`:** a bare `bundle exec fastlane` runs `fastlane.bat`, which cuts
     multi-line notes to their first line, with no error.
   - Only `notes`, `skip_tests`, `dry_run`, `diagnostics` and `allow_unmerged` exist, and flags
     take only `true`/`false`. `diagnostics` is rejected on an app without a diagnostics build.
   - Put notes in **single quotes** and write an apostrophe as `'\''`.
   - Don't edit, commit, check out or stash anything in the repo until the lane finishes. It
     aborts if HEAD or the tree changes under it.
4. **Refusals before the build are gates, not bugs.** Relay them:
   - not the tip of the default branch: merge, pull, or push first;
   - CI still running: wait for green, then rerun. Never poll CI on the developer's behalf;
   - CI red: link the failed run;
   - no checks at all: CI is broken or disabled;
   - `gh` signed out: `gh auth login`.

   Never suggest `allow_unmerged:true` or `skip_tests:true` as a way past a gate unless the
   developer asks.
5. **Report** the summary block: versionCode, commit, built, tag, diagnostics, notes. A
   `diagnostics: OFF` build is a production candidate: after a smoke test,
   `/ship-production version_code:<N>` promotes it as-is. On a real upload, add that testers
   get it from the app's Play Store page via Update, which can take a few minutes. An
   `UNMERGED BUILD` line means production will refuse it.
6. **On failure,** first look for the summary block (`Shipped to internal testers` followed by
   `versionCode:`/`commit:`/`tag:`). If it's there, the upload succeeded: report it as
   shipped and **never rerun** (a rerun uploads again). A tag line saying `PUSH FAILED` or
   `NOT created` means only the tag is missing; relay the hand-run `git tag`/`git push`
   commands. With no summary block the ship failed: quote the fastlane error. A test failure
   means fixing the code, not passing `skip_tests`.
