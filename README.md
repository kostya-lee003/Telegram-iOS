# Telegram-iOS — Contest Setup (Kostya)

This document describes my local environment and the steps I used to build and run **Telegram-iOS** (`release-11.11.2`) on **Apple Silicon** for the iOS contest.

## Environment

- MacBook Pro M1 Max (Apple Silicon)
- macOS: 15.6.1 (Sequoia)
- Xcode: **16.2** (Build version 16C5032a)
- Swift tools version: 6.0.3
- Bazel: **7.3.1** (`bazel-7.3.1-darwin-arm64` placed at `~/bazel-dist/bazel`)
- Repository: fork of `TelegramMessenger/Telegram-iOS`, tag `release-11.11.2`

## Configuration

### 1) Bazel

I downloaded Bazel 7.3.1 for `darwin-arm64` and installed it here:

```bash
mkdir -p ~/bazel-dist
mv bazel-7.3.1-darwin-arm64 ~/bazel-dist/bazel
chmod +x ~/bazel-dist/bazel
```

### 2) Telegram configuration

The configuration file lives **outside** the repository:

```bash
~/telegram-configuration/configuration.json
```

It contains:

```text
bundle_id: org.coolrepka.Telegram
team_id: Z36VGA9KK8
```

### 3) `.bazelrc`

In the project root, I added:

```text
build --action_env=CMAKE_OSX_ARCHITECTURES=arm64
```

This is required to build **tdlib** (`third-party/td`) for **arm64** on Apple Silicon simulators.  
Without it, `libtde2e.a` and `libtdutils.a` were built as `x86_64`, and the linker failed with errors like:

```text
found architecture 'x86_64', required 'arm64'
Undefined symbols for architecture arm64: tde2e_api::...
```

### 4) Generate the Xcode project

Generate the project with:

```bash
python3 build-system/Make/Make.py   --bazel="$HOME/bazel-dist/bazel"   --cacheDir="$HOME/telegram-bazel-cache"   generateProject   --configurationPath="$HOME/telegram-configuration/configuration.json"   --disableExtensions   --disableProvisioningProfiles   --xcodeManagedCodesigning
```
