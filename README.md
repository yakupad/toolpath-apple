# Toolpath

A workshop companion for hobby CNC owners — 3018, Shapeoko, Onefinity,
LongMill, X-Carve and desktop mills. Native SwiftUI for iPhone, iPad
(including iPhone Duo) and Mac.

> Status: early development. Not yet on the App Store.

## What it does
- **Check before you cut** — native G-code parser and analyzer, 3D/2D
  toolpath viewer, simulation, safety score and warnings anchored to the
  exact move.
- **Pre-flight** — a checklist generated from the file, your machine and
  your tools: zero point, stock thickness, tool changes, clamp zone.
- **Run & log** — job timer with Live Activity, Dynamic Island, Apple Watch
  and StandBy; one-tap outcome logging that feeds your cut recipes.
- **Calculate** — deterministic feeds & speeds, recipes, quotes and workshop
  calculators. The numbers always come from formulas, never from an AI.
- **Ask** — offline GRBL/grblHAL/FluidNC alarm decoder and an on-device
  assistant.

## Principles
1. Deterministic trust: cutting values and safety findings come from code
   and curated tables. AI only explains.
2. No login: data syncs through the user's own iCloud; purchases through
   their Apple Account.
3. Free tier costs nothing to run: no cloud AI for free users.

## Requirements
- Xcode 27, Swift 6
- iOS / iPadOS / macOS 26 or later

## Building
```
brew install xcodegen
xcodegen generate
open Toolpath.xcodeproj
```
Core logic tests: `cd Packages/ToolpathKit && swift test`.

## Configuration
No secrets live in this repository. Local values go in
`Config/Secrets.xcconfig` (git-ignored); copy
`Config/Secrets.example.xcconfig` to get started.

## License
Source-available, all rights reserved. You can read the code; you can't
copy, redistribute or ship it. See [LICENSE](LICENSE).
