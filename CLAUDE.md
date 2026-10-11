# Toolpath (native Apple app)

Public repo, source-available license. Product research, plan and design
notes live in a private planning vault, not in this repo.

## Hard rules
- **Never commit secrets**: no API keys, `.p8`, certificates, Worker secrets,
  real `Config/Secrets.xcconfig`, personal emails or tokens. Use
  `Config/Secrets.example.xcconfig` placeholders and CI secrets.
- Cutting values and safety findings are deterministic code — never LLM output.
- Free tier must make zero cloud-AI calls (see vault: `03 Plan/AI Cost Strategy.md`).
- No login: SwiftData + CloudKit private DB, StoreKit 2.
- Communication with the developer is Turkish; code, comments, commits are English.
- Commits use the repo-local identity (GitHub noreply email); no Co-Authored-By trailer.

## App identity
- App Store Connect app "Toolpath", bundle `com.yakupad.toolpath` (Universal).
- Min OS: iOS / iPadOS / macOS 26. Xcode 27, Swift 6.

## Signing & iCloud
- SwiftData uses the CloudKit private database `iCloud.com.yakupad.toolpath`
  (free sync, no login). App Group: `group.com.yakupad.toolpath` (app + widget).
- Builds you *run* must be signed (simulator: plain `xcodebuild build`, ad-hoc).
  `CODE_SIGNING_ALLOWED=NO` strips the iCloud entitlement and CloudKit traps at
  launch — use it only for compile-only checks (as CI does).
- Release signing: fastlane match, readonly, from the private shared repo
  `yakupad/apple-signing`. `fastlane ios bootstrap_signing` (with
  `MATCH_FORCE=1` after adding capabilities) refreshes profiles; the password
  lives in the macOS Keychain item "fastlane-match apple-signing" and the
  `MATCH_PASSWORD` Actions secret — never in the repo.
- TestFlight: `.github/workflows/testflight.yml` (manual). Secrets:
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT_BASE64`, `MATCH_PASSWORD`,
  `MATCH_REPO_TOKEN` (fine-grained PAT, Contents: read on apple-signing).
