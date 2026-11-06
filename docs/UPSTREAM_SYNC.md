# Merging upstream releases

Ivy tracks stable releases of [Signal-iOS](https://github.com/signalapp/Signal-iOS). Upstream history is kept, so each release is brought in with a normal `git merge`.

Merge every upstream stable release, at least once a month. Signal-iOS builds expire about 90 days after release and the server stops accepting old client versions, so falling behind breaks the app.

A weekly workflow (`.github/workflows/upstream-watch.yml`) checks for new stable releases and opens an issue named "Merge Signal-iOS <tag>" for each one. To check by hand:

```
python3 Scripts/ivy/upstream.py status
```

Stable tags have no suffix (for example `8.32.0.1910`); beta tags end in `-beta`.

## Merging

`Scripts/ivy/upstream.py` does the mechanical parts. Start from an up-to-date `main` with a clean working tree:

```
python3 Scripts/ivy/upstream.py merge            # the latest stable release
python3 Scripts/ivy/upstream.py merge 8.33.0.2000  # or a specific one
```

It creates a branch named after the release (`merge-upstream-8-33`), fetches the tag, merges it without committing, resolves conflicts in `.github/` and `Pods` with Ivy's side, sets the client version (step 5) and lists the files that are left. Steps 1 to 3 below describe what it does, for doing it by hand.

1. Start from an up-to-date `main` and create a branch named after the release, for example `merge-upstream-8-33`.
2. Fetch the release tag:
   ```
   git fetch --no-tags https://github.com/signalapp/Signal-iOS.git refs/tags/<tag>:refs/tags/upstream/<tag>
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
5. Set the client identity: in `Config/Ivy.xcconfig`, set `IVY_UPSTREAM_MARKETING_VERSION` and `IVY_UPSTREAM_BUILD_NUMBER` to the merged release (for `8.33.0.2000`: `8.33` and `2000`). Ivy reports exactly this version to Signal's servers. `python3 Scripts/ivy/upstream.py set-version <tag>` does this and updates the README.
   After committing the merge, check that no Ivy change got lost:
   ```
   python3 Scripts/ivy/upstream.py markers
   ```
   It lists files with fewer `// Ivy:` markers than on `main`. Each one needs a look: usually upstream rewrote the code around an Ivy change and the conflict resolution dropped it.
6. Update dependencies: `make dependencies`. If `Podfile.lock` changed, commit it.
   If the merge changes the libsignal, RingRTC or MobileCoin version in the `Podfile`, pushing the branch starts the "Mac Catalyst dependencies" workflow, which builds and publishes the Mac versions (WebRTC takes a few hours). Then copy each new release's tag, asset name and SHA-256 into `Scripts/ivy/catalyst-dependencies.json` and commit it; the Mac build uses them from then on.
7. Check the app name rules against the new strings:
   ```
   python3 Scripts/ivy/app_name.py check Scripts/ivy/app-name-rules.json Signal/translations
   ```
   For every reported string, decide which occurrences of "Signal" mean the app and update `Scripts/ivy/app-name-rules.json` (see [TRANSLATIONS.md](TRANSLATIONS.md)).
8. Build and test both apps locally, push the branch and open a pull request. CI must be green for iOS and macOS.
9. Update the parity matrix if features changed (the README's release was updated in step 5).

## When an upstream change breaks an Ivy feature

Fix it in the merge pull request. If that is not possible in reasonable time, disable the feature on both platforms, mark it `disabled` in [PARITY.md](PARITY.md) with the reason, and open an issue to restore it.
