# Development notes

[Project overview and setup](../README.md#english) · [中文说明](../README.md#chinese)

## Ownership and boundaries

`AndroidMirrorApp` owns one `MirrorStore`, the mirror scene and Settings. `MirrorCommands` defines the menu-bar structure; `PhoneAction` owns shared labels/shortcuts, and `MirrorStore+Commands` owns their eligibility and routing. Window menus reuse `PhoneActionButton`. Credential controls share `MirrorLayout` and `PrimaryActionButton`.

`MirrorStore` coordinates UI state, generation-based cancellation and a single active session. `DeviceRegistry` owns discovery, physical-device identity, deduplication, names and persistence. Credentials are associated with a verified device identity, rather than its changeable IP address. `MirrorPreferences` is the single source of truth for stored settings. Persist enum raw values, not localized labels.

`ADBTransport` is the injectable subprocess boundary. Commands use argument arrays and explicit device selection. Do not interpolate user text into a shell expression. `MirrorSession` owns media/control sockets and cleanup; server version, protocol and socket ordering must change together. An audio capability fallback must affect both server arguments and client socket creation.

`AndroidCapabilities`, `PhoneLockState`, `KeyguardStatus`, `AndroidDisplayGeometry` and `Endpoint` are independently testable parsers/policies. They do not depend on views or manufacturer names. Missing/conflicting state stays unknown. An unknown lock state must not authorize credential entry.

`UnlockInputPreparation` checks UHID access and registers the hardware keyboard before navigation. `UnlockPreparation` performs only wake/navigation/readiness checks; no password enters its ADB commands. Credential submission remains a single operation after a fresh lock check. Retry navigation only on confirmed hidden state, never resubmit a password automatically. Release any temporary Unicode automation session before starting keyguard navigation.

The Android helpers run as temporary shell JARs. `AutomationSession` centralizes the UiAutomation lifecycle and keeps existing accessibility services active. The keyguard helper only focuses already visible credential fields in trusted SystemUI/keyguard windows; it must not click biometric controls or read/set password text. `TextServer` refuses password fields and never uses the clipboard.

Keep decoder/presentation and audio buffering off SwiftUI's per-frame state path. Publish only geometry/session changes to UI state. Stop old generation callbacks before replacing a session, restore owned screen settings, remove only owned ADB forwards and temporary files, and retain no user text in logs.

## Localization

1. Put app-owned visible strings behind `L10n.tr` or `L10n.format`, including AppKit panels, accessibility labels, errors and LocalAuthentication reasons.
2. Add the English key and translation to both `Localization/en.lproj/Localizable.strings` and `Localization/zh-Hans.lproj/Localizable.strings`. Keep format placeholders identical. Dynamic phone names and ADB's external diagnostics remain original data.
3. Localize bundle metadata in `Assets/Localization`. Help is selected through `L10n.guideURL`; update both `Guide-en.html` and `Guide-zh-Hans.html` and their shared stylesheet.
4. Run `python3 script/verify_localizations.py` and the Swift localization tests. Use app-specific `-AppleLanguages` launch arguments to inspect English/Chinese without changing global system preferences.
5. Inspect long English labels in the narrow phone window and every Settings tab. Keep field/button widths consistent; allow explanatory text to wrap.

The main app declares English and Simplified Chinese; SwiftPM's resource bundle declares English as its development language. No custom language preference overrides the system's app language.

## Android compatibility validation

For a new Android variant, capture only non-sensitive state metadata with the device owner's authorization. Add a sanitized fixture or response string and a regression test before changing parser precedence. Do not collect passwords, editor contents, screen captures or full UI hierarchies for a parser fixture.

| Scenario | Expected behavior |
| --- | --- |
| API below 21 | Explain the unsupported mirroring requirement |
| API 21–23 | USB mirroring/control; no direct Unicode helper or Mac audio |
| API 24–29 | Editable-field Unicode when permitted; audio disabled; video still works |
| API 30 | Audio starts while unlocked; a failed audio stream does not stop video |
| Newer/vendor Android | Detect capabilities; test input permissions and keyguard field variations |
| No readable/writable `/dev/uhid` | Unlock uses compatibility input; do not register UHID |
| Phone initially sleeping | Idempotent wake, wait until fully awake, then swipe |
| First swipe ignored | Recheck hidden state and retry navigation in the same request |
| Primary prompt opening | Wait; do not mistake scheduled visibility for readiness |
| Alternate biometric prompt | Do not treat it as the password page |
| User unlocks during preparation | Cancel credential submission; never type into the foreground app |
| Portrait/landscape, tablet, foldable | Read active primary viewport; use wm/video fallback if unavailable |
| External display attached | Ignore external viewport coordinates for primary-phone gestures |
| IPv4/DNS/IPv6, changed Wi-Fi port | Parse endpoint safely and verify physical device identity |
| View-only and screen-off control | View-only accepts no Mac input; controlled display-off does not pulse wake commands |
| Disconnect, cancellation, process failure | Release sockets, restore owned screen timeout and clean owned resources |
| Secondary/clone foreground user | Direct Unicode refuses non-main users; no APK installation into any profile |

Pure tests cannot establish that a vendor accepts the real password, that protected media is capturable, or that wireless video is smooth. Validate those separately on authorized devices without recording secrets. The optional `ANDROIDMIRROR_TEST_UNLOCK_DEVICE` test only prepares the prompt; it never submits a credential. `ANDROIDMIRROR_TEST_REQUIRE_LOCKED=1` waits for a locked state, and `ANDROIDMIRROR_TEST_UNLOCK_KEYBOARD=1` includes temporary keyboard attachment.

## Build assets and diagnostics

The checked-in JAR's companion source fingerprint avoids rebuilds caused only by checkout timestamps. Changing Java source causes `build_and_run.sh` to rebuild it with the locally selected SDK. Rebuild intentionally with `script/build_android_text.sh`; never update the fingerprint without compiling the JAR.

`script/check.sh` runs catalog validation, Swift regressions and the pure Java text-edit test. JDK/SDK resolution is centralized in the build scripts. The icon is generated programmatically from `Assets/AppIcon-Source.png` by `script/create_icon.swift`.

Use `script/build_and_run.sh --debug`, `--logs` or `--telemetry` for local diagnosis. Logs should describe operational state and aggregate timing, never credentials or clipboard/editor content. Packaging uses ad-hoc signing; release signing and notarization need a separate distribution workflow.

## Release packaging

`VERSION` owns the app and DMG version. `script/create_dmg.sh` builds both macOS architectures, verifies nested signatures and architecture slices, packages ADB and its notice, and produces the DMG plus SHA-256 checksums. Packaging gives resources normal distribution read permissions and omits local extended attributes/ACLs from the staged app.

Before publishing, mount the verified image read-only, confirm the application/Applications link/licenses and both localization catalogs, launch the packaged app, and compare the uploaded assets with `SHA256SUMS.txt`. Point the release tag at the tested source commit. The current build is ad-hoc signed and not notarized; release notes and installation instructions must state that accurately. Do not represent local signature verification as Developer ID approval or Apple notarization.

### Video quality and color regression checks

`VideoQuality` controls encoder bandwidth independently of `maxSize`; preserve it in capability negotiation. Settings changes restart the media session. `VideoDisplayBuffer` chooses full/video-range output from the encoded description, propagates missing source color attachments without overriding decoder conversions, and refreshes cached image descriptions when attachments change. Do not label an SDR stream as P3/HDR or relabel limited-range bytes as full-range bytes.

The limited/full-range gradient fixtures are synthetic grayscale ramps, generated with `python3 script/generate_video_color_fixtures.py` (FFmpeg with libx264 is required only for regeneration). Regression checks decode through VideoToolbox and measure endpoints/intermediate levels as well as attachment changes. USB transport tests cover preference before connection, active-session stability and unauthorized endpoints.

### USB entry and direct mirroring

`DeviceRegistry.usbDevices` tracks authorized physical transports independently of saved records and transport deduplication. Forgetting a record suppresses wireless rediscovery, but not a newly attached authorized USB endpoint. `MirrorStore` selects a new USB transport only while idle and after authentication finishes; attachments during a session are deferred until disconnection. USB entry uses the manual phone-password form even if a saved credential exists. Explicit USB password entry can unlock before a view-only session without enabling ordinary mouse/keyboard control.

`MirrorConnectionIntent.direct` is session-scoped, disables input and lock overlays, and preserves picture/audio choices while disabling wake and screen-timeout automation. It must survive settings restarts and recovery after the phone is manually unlocked. Disconnect clears the intent. Only an explicit unlock command restores the standard credential workflow; lock polling never reads passwords. Tests use synthetic devices to exercise entry, deletion, attachment deferral, replugging and direct-session credential guards without opening real ADB sessions.
