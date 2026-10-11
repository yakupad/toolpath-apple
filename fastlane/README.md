fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios bootstrap_signing

```sh
[bundle exec] fastlane ios bootstrap_signing
```

One-time (or after adding capabilities): create or refresh certs and profiles

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload the iOS app to TestFlight

----


## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload the Mac app to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
