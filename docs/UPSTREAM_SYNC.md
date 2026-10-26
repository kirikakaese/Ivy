# Merging upstream releases

Ivy tracks stable releases of [Signal-iOS](https://github.com/signalapp/Signal-iOS). Upstream history is kept, so each release is brought in with a normal `git merge`.

Merge every upstream stable release, at least once a month. Signal-iOS builds expire about 90 days after release and the server stops accepting old client versions, so falling behind breaks the app.

## Finding the latest stable release

Stable tags have no suffix (for example `8.32.0.1910`); beta tags end in `-beta`.

```
git ls-remote --tags --refs https://github.com/signalapp/Signal-iOS \
  | awk -F/ '{print $3}' | grep -v -- '-beta' | sort -V | tail -1
```

## Merging

1. Start from an up-to-date `main` and create a branch named after the release, for example `merge-upstream-8-33`.
2. Fetch the release tag:
   ```
   git remote add upstream https://github.com/signalapp/Signal-iOS.git   # once
   git fetch --no-tags upstream refs/tags/<tag>:refs/tags/upstream/<tag>
   ```
3. Merge it:
   ```
   git merge --no-ff upstream/<tag> -m "Merge Signal-iOS <tag>"
   ```
4. Resolve conflicts. Ivy's changes inside upstream files are marked with `// Ivy:` comments, which makes them easy to find. Typical cases:
   - `Pods`: upstream updates its Pods submodule pointer. Ivy does not use the submodule; keep it removed.
   - `.github/`: upstream workflow changes do not apply to Ivy; keep Ivy's versions.
   - `Signal.xcodeproj/project.pbxproj`: keep both sides' additions, then re-apply Ivy's settings (product name, bundle ID prefix, build phases) if upstream changed the same lines.
   - `Info.plist` files of the app and its extensions: upstream changes the version number there. Keep Ivy's `$(IVY_UPSTREAM_MARKETING_VERSION)` and `$(IVY_UPSTREAM_BUILD_NUMBER).$(IVY_BUILD)` and update `Config/Ivy.xcconfig` instead (next step).
5. Set the client identity: in `Config/Ivy.xcconfig`, set `IVY_UPSTREAM_MARKETING_VERSION` and `IVY_UPSTREAM_BUILD_NUMBER` to the merged release (for `8.33.0.2000`: `8.33` and `2000`). Ivy reports exactly this version to Signal's servers.
6. Update dependencies: `make dependencies`. If `Podfile.lock` changed, commit it.
   If the merge changes the libsignal, RingRTC or MobileCoin version in the `Podfile`, pushing the branch starts the "Mac Catalyst dependencies" workflow, which builds and publishes the Mac versions (WebRTC takes a few hours). Then copy each new release's tag, asset name and SHA-256 into `Scripts/ivy/catalyst-dependencies.json` and commit it; the Mac build uses them from then on.
7. Check the app name rules against the new strings:
   ```
   python3 Scripts/ivy/app_name.py check Scripts/ivy/app-name-rules.json Signal/translations
   ```
   For every reported string, decide which occurrences of "Signal" mean the app and update `Scripts/ivy/app-name-rules.json` (see [TRANSLATIONS.md](TRANSLATIONS.md)).
8. Build and test both apps locally, push the branch and open a pull request. CI must be green for iOS and macOS.
9. Update the upstream release named in the README, and the parity matrix if features changed.

## When an upstream change breaks an Ivy feature

Fix it in the merge pull request. If that is not possible in reasonable time, disable the feature on both platforms, mark it `disabled` in [PARITY.md](PARITY.md) with the reason, and open an issue to restore it.
