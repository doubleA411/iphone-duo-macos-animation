# macTilt

A native macOS experiment that ties a desktop fold-and-frost effect to a MacBook's physical lid angle. Closing stretches the desktop upward while keeping the bottom edge anchored, narrows the upper sides, and progressively blurs the top. Opening reverses the effect; pausing the lid holds its position.

Based on [lqSky7/iphone-duo-macos-animation](https://github.com/lqSky7/iphone-duo-macos-animation). This fork retains the upstream history and credits. It is an experimental adaptation, not an Apple product or an exact reproduction of Apple's animations.

## Licensing status

The upstream repository did not include a license when this fork was prepared. **This repository is not yet offered under an open-source license.** Publishing a GitHub fork does not grant unrestricted reuse or redistribution rights. No MIT or other blanket license is asserted over upstream code or artwork. A fully licensed release requires permission from the upstream rights holders or replacement of their material.

## Requirements

- macOS 26 or newer, because the settings interface uses the current SwiftUI glass APIs.
- Xcode command-line tools with the macOS 26 SDK.
- A MacBook with an accessible lid-angle sensor and Metal support. Hardware access was verified on an M3 Pro MacBook Pro; other models are unverified.
- Screen Recording permission for desktop capture. Wallpaper and bundled artwork are alternative sources.

## Build and run

```sh
./build.sh
open build/macTilt.app
```

The script builds locally and does not install into `/Applications`, remove other apps, download dependencies, or change privacy settings. The Metal shader is compiled by the system at launch.

For a stable identity across local rebuilds, use an existing code-signing certificate:

```sh
MACTILT_SIGNING_IDENTITY="Your Code Signing Certificate" ./build.sh
```

The default uses ad-hoc signing. Rebuilding an ad-hoc app can invalidate its previous Screen Recording grant. The project contains no signing keys or certificates.

## Use

Open the laptop icon in the menu bar for settings. Start and full-fold angles control the active range. The screen source, blur strength, and follow responsiveness can be adjusted there.

Preview runs in a separate closable window, automatically ends after 15 seconds, and can be dismissed with Escape while macTilt is focused. The control panel uses normal window behavior. Quit macTilt from its menu to remove the effect.

If Screen Recording is enabled in System Settings but capture fails, first quit and reopen the same app build. If the app's signing identity changed, remove its old entry and add the current `.app` under Privacy & Security → Screen & System Audio Recording. The permission indicator verifies an actual small ScreenCaptureKit capture.

## Validation

```sh
./test.sh
```

Motion regression checks cover startup at a low angle, closing and opening, pauses in both directions, reversal, full opening, reset, wake, invalid samples, and custom thresholds. The shader was also rendered locally at four stages and inspected. Real-world lid timing, sleep/wake transitions, fullscreen apps, and multi-monitor behavior still need broader testing.

## Limitations and privacy

The app captures a desktop snapshot for the effect rather than continuously animating live windows. Captures are processed in memory; the app does not transmit them or save them to disk. The app polls the sensor at 60 Hz; the renderer pauses when inactive. This is not a zero-power background app.

Normal macOS sleep behavior remains enabled. Animation cannot render while the display sleeps. On wake, old screen textures are cleared and wallpaper is used until a fresh capture is available. The fullscreen effect targets the built-in display. The supplied build is neither notarized nor distributed as a signed release.

## Credits

- Original app, UI, sensor integration, rendering infrastructure, and bundled artwork: [lqSky7](https://github.com/lqSky7/iphone-duo-macos-animation).
- Sensor research credited by upstream: [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor).
- This fork: bidirectional motion and pause handling, preview safeguards, built-in display selection, capture verification, a revised shader, and a portable local build.
