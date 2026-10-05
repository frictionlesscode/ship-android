---
name: ship-production
description: Promote a build of an Android app using ship_android (Driftwell, RuckPace) that is already on Google Play's internal track to Production, unchanged, and send it for review. Use when the developer says promote/ship/release to production or "send v12 to prod". Args - version_code:N (required), rollout:0.2 (staged), dry_run:true, trust_untagged:true.
---

# Ship to production

Runs `fastlane android production` from the shared `ship_android` gem. It promotes an
internal-track release to Production with no rebuild and no upload, so the public gets the
exact bytes that were smoke-tested. Read the app's `fastlane/Fastfile` `package:` line to name
the app.

1. **Pick the versionCode.** Use the one the developer names. Otherwise take the newest
   `testers/android/v*` tag (`git tag --list 'testers/android/*' --sort=-v:refname | head -1`)
   and say which one you picked.
2. **Confirm unless dry_run.** This reaches every user once Google approves it. Show the app,
   the versionCode, the commit its tag points at (`git log -1 --format='%h %s' testers/android/v<N>`)
   and the rollout (full unless `rollout:` was given), and ask whether it was smoke-tested on a
   phone. Skip only if the developer already said in this conversation to promote that code.
3. **Run** from the repo root, in the foreground (under a minute):
   `export PATH="/c/Ruby33-x64/bin:$PATH" && bundle exec ruby -S fastlane android production version_code:<N>`
   plus `rollout:0.2` / `dry_run:true` if asked. Only `version_code`, `rollout`, `dry_run` and
   `trust_untagged` exist.
4. **Refusals are guards, not bugs.** The lane refuses:
   - a code not on the internal track;
   - a build tagged `unmerged=true`;
   - a build tagged `diagnostics=on`;
   - a tag that doesn't record diagnostics, on an app that has them;
   - a tagged commit that isn't on the default branch, or isn't green.

   Relay the message. Pass `trust_untagged:true` only when the developer confirms that build
   had no diagnostics tools. It never overrides `diagnostics=on` or `unmerged=true`.
5. **Report** versionCode, tag and rollout. If Play rejects the promotion because the app has
   never been released to production, say that the Play Console needs its first-release steps
   done (store listing, content rating, data safety, and closed testing on a personal account).
