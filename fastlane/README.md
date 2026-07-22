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

### ios check

```sh
[bundle exec] fastlane ios check
```

煙霧測試：驗證 API Key 認證與 App Store Connect 連線（不 build）

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

建立/同步簽章憑證到 certs repo（首次設定或憑證更新時跑）

### ios build_only

```sh
[bundle exec] fastlane ios build_only
```

本機驗證：用 match 描述檔打包 IPA（不上傳）

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build 並上傳到 TestFlight

build number 自動遞增；marketing version 讀專案設定（人工在 Xcode 改並 commit）

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
