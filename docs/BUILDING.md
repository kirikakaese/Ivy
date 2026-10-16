# Building Ivy

Ivy can only be built on a Mac with Xcode. The upstream instructions in the root `BUILDING.md` describe Signal's setup; this document describes Ivy's.

## Requirements

- A Mac with Apple Silicon.
- The Xcode version listed in `.xcode-version`.
- Ruby (the version in `.ruby-version`) with Bundler, for CocoaPods.
- Git.

## 1. Clone

```
git clone --recurse-submodules https://github.com/kirikakaese/Ivy.git
cd Ivy
```

## 2. Dependencies

```
make dependencies
```

This installs CocoaPods with Bundler, installs all pods from `Podfile.lock` into `Pods/`, and downloads the prebuilt libsignal and RingRTC libraries. Run it again whenever `Podfile.lock` changes, for example after an upstream merge.

## 3. Open in Xcode

```
open Signal.xcworkspace
```

The app target is still called `Signal` inside the project (the upstream name), but it builds `Ivy.app`.

### Running on the simulator

Select the `Signal` scheme and an iPhone or iPad simulator, then build and run. No signing setup is needed.

### Running on your own device

1. In the project settings, select your team for the `Signal`, `SignalShareExtension` and `SignalNSE` targets.
2. If your team cannot use the bundle ID prefix `io.github.kirikakaese`, change `SIGNAL_BUNDLEID_PREFIX` in the project's build settings.
3. Some capabilities in the upstream entitlements need a paid developer account. Remove the ones your account cannot use (Apple Pay, carrier-constrained networking, Wi-Fi Aware, iCloud) from the entitlements of your local build.

## Tests

```
Scripts/ivy/ci-build.sh full
```

Ivy's own scripts have Python unit tests that run on any system:

```
python3 -m unittest discover -s Scripts/ivy -p 'test_*.py'
```

## Continuous integration

GitHub Actions checks every pull request (`.github/workflows/ci.yml`). Draft pull requests get a fast check that builds the app and all test bundles; pull requests that are ready for review, pushes to `main` and manual runs also run the full test suite. Build products are cached between runs.

The Mac Catalyst variants of libsignal, RingRTC/WebRTC and MobileCoin are built by `.github/workflows/catalyst-dependencies.yml`. It runs automatically when the pinned versions in the `Podfile` change and publishes the results as release assets, so it only does real work about once per upstream dependency update.
