# LUME Android Build Candidate

Source version: `0.35.0+35`

This branch contains an exact textual bundle of the 52 Flutter source/test files that passed the CP35 local source-level regression. The GitHub Actions workflow reconstructs the source only after validating:

- 87 sequential chunks (`000` through `086`)
- exact bundle length: `185942` bytes
- SHA-256: `a9c6409be857d97b46217f4ee271e6d0dc03e10a68d87fa6a62e93fc3e5dd616`
- exact bundle file count: 52
- every output path stays under `flutter/`

The workflow then runs Flutter dependency resolution, `flutter analyze --fatal-infos`, Flutter tests, and a real release APK build. A successful job uploads the APK and its SHA-256 as the `lume-release-apk` artifact.

A green workflow proves compilation/build gates, not full device QA. The APK still requires installation and runtime acceptance on Android before final-release status.
