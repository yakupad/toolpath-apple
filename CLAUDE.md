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
