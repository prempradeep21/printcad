# Setup (MacBook, one time)

## 0. Do you need the $99 Apple Developer account?

No, not to start. A free Apple ID ("Personal Team" in Xcode) can install your app on your own iPad and iPhone.

| | Free Personal Team | Paid ($99/yr) |
| --- | --- | --- |
| Run on Mac ("Designed for iPad") | Yes | Yes |
| Install on your iPad/iPhone | Yes, by cable from Xcode | Yes, cable, wireless or TestFlight |
| How long the install keeps working | 7 days, then rebuild and reinstall | 1 year |
| Limits | 3 devices, 3 apps per device, 10 App IDs per 7 days | Effectively none for you |
| iCloud sync between devices | Not available on Personal Team (as far as I know) | Yes |

Plan: start free. Buy the account when you reach M3 (sync), or earlier if weekly reinstalls get annoying.
Tip: keep one bundle ID (`com.prem.printcad`) forever so you don't burn the 10 App IDs limit.

## 1. Check your Mac chip

Apple menu → About This Mac. You need **Apple M-series** to run the iPad build on the Mac ("Designed for iPad"). Intel Macs can't.

## 2. Install tools

1. Install **Xcode 26 or newer** from the App Store; open it once and let it install components, including the iOS platform.
2. Install Homebrew (https://brew.sh) if you don't have it.
3. `brew install git-lfs cmake gh`
4. `git lfs install`
5. Claude Code: already installed per your setup; docs at https://docs.claude.com/en/docs/claude-code/overview

## 3. Fork and clone

```bash
gh auth login                                   # once
gh repo fork laanlabs/openshape3d --clone --fork-name printcad
cd printcad
git lfs pull
git checkout -b printcad/main
```

## 4. Verify the OCCT binary came down

```bash
du -sh ThirdParty/OCCT.xcframework
find ThirdParty/OCCT.xcframework -name "*.a" -size -10k
```

- The framework should be hundreds of MB.
- The `find` command should print nothing. Tiny `.a` files are Git LFS pointers: run `git lfs pull` again.
- If the framework is missing entirely, the README describes rebuilding it with `scripts/build_occt_ios.sh` (needs OCCT source + an iOS CMake toolchain). Ask Claude Code to walk you through it.

## 5. Signing

1. Xcode → Settings → Accounts → `+` → add your Apple ID.
2. Open `openshape3d.xcodeproj`.
3. Select the app target → Signing & Capabilities → Team: *Your Name (Personal Team)*.
4. Bundle Identifier: `com.prem.printcad`.
5. Do the same for the test targets if Xcode complains.

## 6. First build (simulator)

Scheme `openshape3d`, destination an iPad simulator, press Run (⌘R). Then run tests with ⌘U or:

```bash
xcodebuild test -project openshape3d.xcodeproj -scheme openshape3d \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

If that simulator name doesn't exist, list them with `xcrun simctl list devices available` and use one that does.

## 7. Run on the Mac

Native Mac Catalyst build (decided 2026-09-27; no Apple team needed):

```bash
xcodebuild build -project openshape3d.xcodeproj -scheme openshape3d \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData-mac \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
open build/DerivedData-mac/Build/Products/Debug-maccatalyst/openshape3d.app
```

In Xcode: destination **My Mac (Mac Catalyst)** → Run.

## 8. Run on your iPad

1. Connect by cable; trust the Mac on the iPad.
2. iPad: Settings → Privacy & Security → Developer Mode → On (restarts).
3. Select the iPad as destination → Run.
4. First launch: iPad Settings → General → VPN & Device Management → trust your developer certificate.
5. Every 7 days: plug in and press Run again.
