# Android Mirror · 安卓镜像

[English](#english) · [简体中文](#chinese)

<a id="english"></a>

## English

Android Mirror is a native macOS SwiftUI app for viewing and controlling an Android phone over USB or Android Wireless debugging. It uses ADB and the scrcpy server; no root access or installed companion app is required.

The interface is a single phone-shaped window: select a device at the top, connect or unlock in the center, and find controls in the **…** menu. The window resizes in proportion to the phone screen. English and Simplified Chinese follow the system's preferred app language, with English as the fallback.

### Features

- Wireless pairing by QR code or six-digit pairing code, plus USB connections.
- Saved devices with discovery, renaming and removal.
- Mouse control, scrolling, Mac keyboard input and text clipboard synchronization.
- Direct Unicode text entry into supported editable fields, separate from the clipboard.
- **Control Phone** and **View Only** modes.
- Phone or Mac speaker output, resolution presets, screenshots and screen rotation.
- Keep the phone awake while controlling, optionally turn its physical display off, and restore the screen timeout on disconnect.
- Phone PIN/password entry, optional encrypted password storage, and autofill authorized by Touch ID or the current Mac account's login password.

### Requirements and compatibility

| Feature | Requirement |
| --- | --- |
| Mac app | macOS 14 or later |
| USB mirroring and control | Android 5.0 or later; USB debugging authorized for the Mac |
| Wireless debugging pairing | Android 11 or later; phone and Mac on a reachable local network |
| Mac audio | Android 11 or later; Android 11 must be unlocked when audio capture starts |
| Direct Unicode entry | Android 7.0 or later, main Android user (user 0), and an editable field exposing Android's text action |
| Saved-password protection | A Mac with Secure Enclave support and macOS authentication |

The app checks Android API level, UHID access, keyguard state and primary-display geometry instead of matching manufacturer names. Older platforms retain supported features: audio is disabled below Android 11, and unavailable UHID input falls back to compatibility input for unlocking. USB remains the connection method for Android versions without Wireless debugging pairing. These code paths do not guarantee that every manufacturer's security policy permits remote input or unlocking.

The platform requirements come from [scrcpy](https://github.com/Genymobile/scrcpy/tree/v3.3.4), its [audio documentation](https://github.com/Genymobile/scrcpy/blob/v3.3.4/doc/audio.md), and [Android Wireless debugging documentation](https://developer.android.com/tools/adb#wireless-android11-command-line).

### Install and connect

Download the DMG from [GitHub Releases](https://github.com/lopleec/Android_Mirror/releases/latest). Open it and drag **AndroidMirror** into **Applications**. Open the app from Applications. The universal download supports Apple Silicon and Intel Macs running macOS 14+ and includes ADB.

This release is locally ad-hoc signed and **not notarized**. macOS may block the first launch of the downloaded app; review the publisher/source and use the per-app **Open Anyway** option in **System Settings → Privacy & Security** if you choose to allow it. Do not disable Gatekeeper globally. Developer ID signing/notarization is not included in this distribution. See [Apple’s opening guidance](https://support.apple.com/en-us/102445).

To build from source instead, follow the instructions below and open `dist/AndroidMirror.app`.

If ADB is unavailable, use **Settings → Devices → Advanced Connection Settings → Download ADB from Google (Platform-Tools)**. Extract the macOS download and use **Choose ADB…** to select its `adb` executable. The app also searches its bundled tools, common Homebrew locations and the default Android SDK location.

**Wireless connection**

1. Enable Developer options and **Wireless debugging** on the phone. Connect the phone and Mac to the same Wi-Fi, and allow local network access if macOS asks.
2. In Android Mirror, click **Connect Phone** or choose **… → Connect Phone…**.
3. For QR pairing, open **Wireless debugging → Pair device with QR code** on the phone and scan the app's code. Use that settings scanner, rather than the camera app. Codes expire after two minutes.
4. For code pairing, select **Pairing Code** and enter the IP address, pairing port and six-digit code from the phone's pairing dialog.
5. The app discovers the connection port after pairing. If discovery is unavailable, enter the connection port from the main Wireless debugging page. The pairing port and connection port are different.

Manual connections accept IPv4, hostnames and IPv6. Enter the host and port in their separate fields; a scoped IPv6 host can look like `fe80::1234%en0`. The scope must name the appropriate network interface on the Mac.

**USB connection**

Enable **USB debugging**, connect a data-capable cable, and accept the phone's debugging authorization prompt. Select the phone from the top device menu, then click **Connect**. An unauthorized phone cannot be controlled until permission is granted on the phone.

### Use the app

Select devices from the centered top menu. To rename or remove a saved device, open **Settings → Devices**. Removal deletes this app's record and saved password; it does not revoke the phone's ADB pairing. Revoke that separately in the phone's Wireless debugging settings when needed.

Use **… → Interaction** to switch modes. **View Only** leaves operation on the phone and disables Mac input and clipboard sync. In **Settings → General**, choose the audio output, resolution, keep-awake behavior, physical-screen power behavior and window pinning. Changing the audio output or resolution restarts the media session.

Click the mirrored screen to focus keyboard input. Drag to swipe, hold to long-press, scroll to move a page, and right-click to go back. Mac input methods commit Unicode text directly to supported fields; custom editors, games, protected fields or restricted Android builds may reject that action. The app reports the failure without silently using or changing the clipboard. Explicit copy, cut and paste remain separate operations.

| Shortcut | Action |
| --- | --- |
| ⌘R | Start mirroring / disconnect |
| ⌘⇧N | Add wireless device |
| ⌘1 / ⌘2 / ⌘3 | Home / recent apps / notifications |
| ⌘[ or Esc in the mirror | Back |
| ⌘⇧S | Save screenshot |
| ⌘⇧O | Wake phone |
| ⌘⇧U | Open phone-password entry |
| ⌘C / ⌘X / ⌘V in the mirror | Copy / cut / paste |

### Unlocking and password privacy

Enter the phone's PIN or password and click **Connect and Unlock** or **Unlock**. The app wakes a sleeping screen, swipes up away from the fingerprint area, waits for the credential prompt and sends the password once. Navigation may retry if the first swipe is ignored; passwords are never retried automatically. If the phone unlocks manually during preparation, the app does not type the password into an app.

**Settings → Password** contains password saving, input method and Mac authentication validity. **Physical Keyboard · US** uses a temporary UHID keyboard when available; **Compatibility Input** is an alternative for systems that reject it. Password entry supports digits and printable ASCII letters/symbols. Patterns, non-ASCII lock passwords and manufacturer-protected prompts should be unlocked on the phone.

Saved passwords are encrypted with Secure Enclave-backed protection and stored in this Mac's Keychain. Showing, changing or deleting one always requires fresh macOS authentication. Autofill may reuse authentication for the selected interval (10 minutes by default), but still requires a click on **Connect** each time. The authorization cache clears when the Mac locks or sleeps, the app quits, or the interval changes. Revealed/edited passwords are concealed after 30 seconds, on window focus loss and when leaving the password settings.

The app cannot bypass Android's lock security, DRM or protected video/audio capture. Some lock screens produce black video; the app uses separately confirmed lock state to show its unlock entry. Macs without Secure Enclave can still use manual password entry.

### Troubleshooting

| Symptom | Check |
| --- | --- |
| Phone absent or offline | Debugging enabled, correct connection port, USB authorization, same network; use **Refresh Devices** |
| QR pairing cannot finish | Use the Wireless debugging scanner; allow local network access; avoid guest Wi-Fi/client isolation; use pairing code or a manual connection if mDNS is blocked |
| Video works but input does not | Some vendors require an additional “USB debugging (Security settings)” permission in Developer options; view-only mode disables input |
| No Mac sound | Select Mac Speaker; on Android 11 unlock and reconnect; apps may prohibit audio capture |
| Video stutters | Try **Smooth · 1280p**, a better Wi-Fi connection or USB; wireless quality and phone encoder load affect latency |
| Unlock fails | Open the password page on the phone, check its password and keyboard layout, or try Compatibility Input; no password is automatically resubmitted |
| Unicode input rejected | Use an ordinary editable field in the main user profile; otherwise use the phone keyboard or explicit paste |
| Saved-password authentication fails | Use the current Mac account's login password or Touch ID; Secure Enclave availability and Keychain access are required |

### Build from source

Required: macOS 14+, Xcode 15.3+ (Swift 5.10+) or a compatible Swift toolchain with the macOS SDK, and Python 3. Set the active developer directory to the intended Xcode installation if multiple versions are installed.

```sh
./script/build_and_run.sh          # Release build, package, sign locally and open
./script/build_and_run.sh --build  # Build the app without opening it
./script/build_and_run.sh --verify # Build, open and verify the process is running
```

To build the Apple Silicon + Intel universal app and a compressed drag-to-Applications disk image:

```sh
./script/create_dmg.sh
```

The image and SHA-256 checksums are written to `dist/`. Versioning comes from the root `VERSION` file. `ANDROID_MIRROR_UNIVERSAL=1` also enables a universal app build through `build_and_run.sh`; the default development build uses the current Mac's architecture.

The result is `dist/AndroidMirror.app`, with bundle identifier `com.lopleec.androidmirror`. Launch the app bundle, rather than the raw SwiftPM executable, so macOS loads its resources, menus and localizations correctly. The script uses local ad-hoc signing; distribution notarization is not configured.

An available ADB executable is copied into the bundle. To select an explicit source:

```sh
ADB=/path/to/platform-tools/adb ./script/build_and_run.sh --build
```

The prebuilt temporary Android service is included. Unchanged Java sources do not require an Android SDK to build the Mac app. To change/rebuild that service, install a JDK 11+ and an Android SDK platform API 34+ with build-tools:

```sh
export JAVA_HOME=/path/to/jdk
export ANDROID_HOME=/path/to/android/sdk
./script/build_android_text.sh
```

`ANDROID_SDK_ROOT` is also recognized. The script finds installed SDK platforms and build-tools automatically; `ANDROID_MIRROR_ANDROID_JAR` and `ANDROID_MIRROR_BUILD_TOOLS` can override the selected paths. The helper targets API 24 and runs temporarily as the ADB shell user. It is not an APK and does not install into the main or clone profiles.

### Development and checks

```sh
python3 script/verify_localizations.py
swift test --scratch-path .build/swiftpm --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/module-cache
./script/check.sh  # Catalog audit, Swift tests and pure Java text tests; requires a JDK
```

Tests use simulated ADB responses by default. An optional device preparation check is skipped unless `ANDROIDMIRROR_TEST_UNLOCK_DEVICE` explicitly names an authorized device; it navigates to the credential prompt without sending a password. See [development notes](docs/DEVELOPMENT.md) for boundaries, localization and the Android validation matrix.

| Directory | Responsibility |
| --- | --- |
| `Sources/AndroidMirror/App` | App scenes, lifecycle and menu-bar commands |
| `Views` | SwiftUI components and the AppKit mirroring surface |
| `Stores` | Session coordination, preferences and device registry |
| `Models` | Protocol/configuration types, shared actions and Android state/capability parsing |
| `Services` | ADB, sockets, video/audio, clipboard, screen and credential workflows |
| `Support` | Localization/resource access, window geometry and privacy helpers |
| `Localization` | English and Simplified Chinese string catalogs |
| `AndroidTextService` | Temporary shell-only text and keyguard helpers |
| `script` / `Tests` | Build/check tooling and regression tests |

All `Sources` subdirectories above are under `Sources/AndroidMirror`. Use `MirrorCommands`, `PhoneAction` and `MirrorStore+Commands` for shared commands; `L10n` for user-visible strings; and `ADBTransport` for injectable device access. Add Android field variants to the pure parsers and cover them with fixtures instead of spreading manufacturer conditions through views.

### License

Android Mirror is released under the [MIT License](LICENSE). Third-party components retain their own licenses.

### Third-party components

- [scrcpy 3.3.4](https://github.com/Genymobile/scrcpy/tree/v3.3.4), Apache 2.0. Its license is included as `Sources/AndroidMirror/Resources/SCRCPY-LICENSE.txt`.
- [Android Platform-Tools](https://developer.android.com/tools/releases/platform-tools): when ADB is packaged, its adjacent `NOTICE.txt` is copied into the app as `Tools/ADB-NOTICE.txt`.
- [AOSP Wireless debugging protocol](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md) defines the pairing QR payload.

[简体中文 ↓](#chinese) · [Back to English](#english)

---

<a id="chinese"></a>

## 简体中文

安卓镜像是一款原生 macOS SwiftUI 应用，通过 USB 或安卓无线调试连接手机，支持投屏和操控。底层使用 ADB 与 scrcpy 服务端，无需 root，也无需在手机安装配套应用。

界面使用单个手机形状的窗口：顶部选择设备，中间连接或解锁，其余操作收在 **…** 菜单中。窗口随手机画面等比例缩放。英文和简体中文默认跟随系统的应用语言偏好，其他语言回退为英文。

### 功能

- 二维码、六位配对码无线配对，以及 USB 连接。
- 保存设备，自动发现，重命名和删除设备。
- 鼠标操控、滚动、Mac 键盘输入和文字剪贴板同步。
- 向支持的可编辑文本框直接提交 Unicode 文字，与剪贴板分离。
- 「操控手机」和「仅投屏」模式。
- 手机或电脑扬声器、分辨率预设、截图和屏幕旋转。
- 操控时保持唤醒，可选关闭手机实体屏幕，断开时恢复原有熄屏时间。
- 手机 PIN / 密码输入，可选加密保存密码，经触控 ID 或当前 Mac 账户登录密码验证后自动填充。

### 环境与兼容性

| 功能 | 要求 |
| --- | --- |
| Mac 应用 | macOS 14 或更高版本 |
| USB 投屏与操控 | Android 5.0 或更高版本，手机已授权 Mac 的 USB 调试 |
| 无线调试配对 | Android 11 或更高版本，手机与 Mac 位于可互通的局域网 |
| 电脑播放手机声音 | Android 11 或更高版本；Android 11 启动声音捕获时需要解锁 |
| 直接输入 Unicode | Android 7.0 或更高版本、主用户 user 0，且输入框提供安卓文本编辑接口 |
| 保存密码的保护 | Mac 支持安全隔区，能够完成 macOS 身份验证 |

应用通过安卓 API 级别、UHID 权限、锁屏状态和主屏幕坐标识别能力，不按厂商品牌硬编码。旧系统保留可用功能：Android 11 以下关闭电脑声音，无法访问 UHID 时解锁采用兼容输入。不支持无线调试配对的系统可使用 USB。这些代码适配不代表每个厂商的安全策略都允许远程输入或解锁。

平台要求可查阅 [scrcpy](https://github.com/Genymobile/scrcpy/tree/v3.3.4)、[声音文档](https://github.com/Genymobile/scrcpy/blob/v3.3.4/doc/audio.md)和 [Android 无线调试文档](https://developer.android.com/tools/adb#wireless-android11-command-line)。

### 安装与连接

从 [GitHub Releases](https://github.com/lopleec/Android_Mirror/releases/latest) 下载 DMG，打开后将 **AndroidMirror** 拖入「应用程序」，再从应用程序目录启动。通用版本支持 macOS 14+ 的 Apple Silicon 和 Intel Mac，并包含 ADB。

当前发行版采用本地 ad-hoc 签名，**未经过 Apple 公证**。macOS 可能阻止首次打开下载的应用；确认发布来源后，可按系统提示在「系统设置 → 隐私与安全性」中使用针对该应用的「仍要打开」。不要全局关闭 Gatekeeper。本发行包尚未配置 Developer ID 签名和公证，操作说明见 [Apple 官方指南](https://support.apple.com/en-us/102445)。

如需从源码构建，请按下方说明操作，然后打开 `dist/AndroidMirror.app`。

若未找到 ADB，进入「设置 → 设备 → 高级连接设置 → 下载 Google 官方 ADB（Platform-Tools）」，解压 macOS 下载包，再通过「选择 ADB…」选中其中的 `adb` 可执行文件。应用也会寻找包内工具、常见 Homebrew 路径和默认 Android SDK 路径。

**无线连接**

1. 在手机上开启开发者选项和「无线调试」，让手机与 Mac 连接同一个 Wi-Fi。macOS 询问本地网络权限时允许访问。
2. 在安卓镜像点击「连接手机」，或选择「… → 连接手机…」。
3. 二维码方式：在手机进入「无线调试 → 使用二维码配对设备」，扫描应用显示的二维码。需要使用这个设置入口，普通相机扫码无效。二维码有效期为两分钟。
4. 配对码方式：选择「配对码」，填写手机配对弹窗中的 IP、配对端口和六位数字。
5. 配对后会自动发现连接端口。无法发现时，填写无线调试主页面上的连接端口；它与配对弹窗的端口不同。

手动连接支持 IPv4、主机名和 IPv6，地址与端口分别填写。带作用域的 IPv6 地址示例为 `fe80::1234%en0`，作用域需对应 Mac 上实际使用的网络接口。

**USB 连接**

开启「USB 调试」，使用可传输数据的线缆连接，并在手机上允许这台 Mac 调试。从顶部设备菜单选择手机，再点击「连接」。未授权设备需要先在手机上允许调试。

### 使用

顶部居中的菜单用于选择设备。「设置 → 设备」可以重命名和删除已保存设备。删除会移除本应用的记录和保存的密码，不会撤销手机上的 ADB 配对；如需撤销，请在手机无线调试设置中另行处理。

「… → 使用方式」可切换操控与仅投屏。「仅投屏」由手机自行操作，关闭 Mac 输入和剪贴板同步。「设置 → 通用」集中设置声音、分辨率、保持唤醒、实体屏幕熄灭和窗口置顶。切换声音输出或分辨率会重新建立媒体连接。

点击镜像获得键盘焦点。拖动模拟滑动，按住模拟长按，滚动浏览页面，右键返回。Mac 输入法选词后直接向支持的输入框提交 Unicode 文字；自定义编辑器、游戏、受保护输入框或受限系统可能拒绝该操作。失败时会显示提示，不会暗中通过剪贴板输入。主动复制、剪切、粘贴仍是独立操作。

| 快捷键 | 操作 |
| --- | --- |
| ⌘R | 开始镜像 / 断开 |
| ⌘⇧N | 添加无线设备 |
| ⌘1 / ⌘2 / ⌘3 | 主屏幕 / 最近任务 / 通知 |
| ⌘[ 或镜像中的 Esc | 返回 |
| ⌘⇧S | 保存截图 |
| ⌘⇧O | 唤醒手机 |
| ⌘⇧U | 打开手机密码输入 |
| 镜像中的 ⌘C / ⌘X / ⌘V | 复制 / 剪切 / 粘贴 |

### 解锁与密码保护

输入手机 PIN 或密码，点击「连接并解锁」或「解锁」。应用会点亮休眠屏幕、避开指纹区域上滑、等待密码界面就绪，再发送一次密码。第一次上滑被忽略时可以重试导航，但不会自动重复提交密码。准备期间若手机被手动解锁，不会将密码输入其他应用。

「设置 → 密码」集中管理保存密码、输入方式和 Mac 验证有效期。「实体键盘 · 美式」在可用时使用临时 UHID 键盘；拒绝硬件键盘的系统可尝试「兼容输入」。支持数字及可打印 ASCII 字母、符号。图案、非 ASCII 锁屏密码或厂商保护的密码页请在手机上解锁。

密码通过安全隔区支持的加密保护保存在本机钥匙串。显示、更改和删除密码始终重新验证 macOS 身份。自动填充可在设置的有效期内复用验证，默认十分钟，但每次仍需要点击「连接」。Mac 锁定或休眠、应用退出、有效期设置改变时会清除验证缓存。显示或编辑中的密码在三十秒后、窗口失去焦点或离开密码设置时隐藏。

应用不能绕过安卓锁屏安全、DRM 或受保护音视频。部分锁屏会输出黑色画面，应用依据独立确认的锁屏状态显示解锁入口。没有安全隔区的 Mac 仍可手动输入手机密码。

### 常见问题

| 情况 | 检查方法 |
| --- | --- |
| 没有设备或设备离线 | 调试是否开启、连接端口是否正确、USB 是否授权、网络是否互通，再刷新设备 |
| 二维码无法完成配对 | 使用无线调试专用扫码入口，允许本地网络访问，避免访客 Wi-Fi / 客户端隔离；mDNS 被阻止时使用配对码或手动连接 |
| 能看画面但不能操控 | 部分厂商需要额外开启开发者选项中的「USB 调试（安全设置）」；仅投屏模式不接受输入 |
| 电脑没有声音 | 选择电脑扬声器；Android 11 先解锁再连接；部分应用禁止声音捕获 |
| 视频卡顿 | 尝试「流畅 · 1280p」、更稳定的 Wi-Fi 或 USB；网络与手机编码负载都会影响延迟 |
| 解锁失败 | 在手机打开密码页，检查密码与键盘布局，或尝试兼容输入；密码不会自动再次提交 |
| Unicode 输入被拒绝 | 在主用户使用常规可编辑文本框，否则使用手机键盘或主动粘贴 |
| 保存密码验证失败 | 使用当前 Mac 账户的登录密码或触控 ID；需要安全隔区和钥匙串访问能力 |

### 源码构建

需要 macOS 14+、Xcode 15.3+（Swift 5.10+）或兼容的 Swift 工具链及 macOS SDK，以及 Python 3。安装多个 Xcode 时，请选择正确的开发者目录。

```sh
./script/build_and_run.sh          # Release 构建、打包、本地签名并打开
./script/build_and_run.sh --build  # 只构建，不打开
./script/build_and_run.sh --verify # 构建、打开并检查进程
```

构建 Apple Silicon + Intel 通用应用及压缩的拖拽安装 DMG：

```sh
./script/create_dmg.sh
```

DMG 和 SHA-256 校验文件位于 `dist/`。版本号来自根目录 `VERSION`。也可给 `build_and_run.sh` 设置 `ANDROID_MIRROR_UNIVERSAL=1` 构建通用应用；默认开发构建采用当前 Mac 的架构。

产物为 `dist/AndroidMirror.app`，标识符为 `com.lopleec.androidmirror`。请启动应用包，以正确加载资源、菜单和本地化，不要直接运行 SwiftPM 裸可执行文件。脚本使用本地 ad-hoc 签名，尚未配置发行公证。

找到可用 ADB 时会将其复制到应用包。也可显式指定：

```sh
ADB=/path/to/platform-tools/adb ./script/build_and_run.sh --build
```

仓库包含预编译的临时安卓服务。Java 源码未变化时，构建 Mac 应用不需要 Android SDK。修改安卓服务后，安装 JDK 11+、API 34+ 的 Android SDK 平台和 build-tools，然后执行：

```sh
export JAVA_HOME=/path/to/jdk
export ANDROID_HOME=/path/to/android/sdk
./script/build_android_text.sh
```

也支持 `ANDROID_SDK_ROOT`。脚本自动寻找已安装的平台和 build-tools；可用 `ANDROID_MIRROR_ANDROID_JAR`、`ANDROID_MIRROR_BUILD_TOOLS` 覆盖选择。服务最低目标为 API 24，以 ADB shell 身份临时运行，不是 APK，不会安装到主空间或分身空间。

### 开发与检查

```sh
python3 script/verify_localizations.py
swift test --scratch-path .build/swiftpm --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/module-cache
./script/check.sh  # 本地化审计、Swift 测试和纯 Java 文本测试，需要 JDK
```

默认测试使用模拟的 ADB 响应，不操作手机。只有显式设置 `ANDROIDMIRROR_TEST_UNLOCK_DEVICE` 指定已授权设备，才启用可选的密码页准备检查；该检查不发送密码。模块边界、本地化规范和安卓验证清单见 [开发文档](docs/DEVELOPMENT.md)。

| 目录 | 职责 |
| --- | --- |
| `Sources/AndroidMirror/App` | 场景、生命周期与菜单栏命令 |
| `Views` | SwiftUI 组件及 AppKit 镜像表面 |
| `Stores` | 会话协调、偏好设置、设备注册 |
| `Models` | 协议配置、统一操作、安卓状态和能力解析 |
| `Services` | ADB、网络、音视频、剪贴板、屏幕及凭据工作流 |
| `Support` | 本地化、资源、窗口几何和隐私辅助 |
| `Localization` | 英文与简体中文字符串表 |
| `AndroidTextService` | 临时 shell 文本和密码页辅助服务 |
| `script` / `Tests` | 构建、检查工具和回归测试 |

上述源码子目录均位于 `Sources/AndroidMirror` 下。操作通过 `MirrorCommands`、`PhoneAction` 与 `MirrorStore+Commands` 共用；可见文字通过 `L10n`；设备访问通过可注入的 `ADBTransport`。新增系统字段应进入独立解析器并添加用例，避免在视图中分散编写厂商判断。

### 许可证

安卓镜像采用 [MIT License](LICENSE)。第三方组件保留各自许可证。

### 第三方组件

- [scrcpy 3.3.4](https://github.com/Genymobile/scrcpy/tree/v3.3.4)，Apache 2.0；许可证随资源保存在 `Sources/AndroidMirror/Resources/SCRCPY-LICENSE.txt`。
- [Android Platform-Tools](https://developer.android.com/tools/releases/platform-tools)：打包 ADB 时，将其相邻的 `NOTICE.txt` 复制为应用中的 `Tools/ADB-NOTICE.txt`。
- [AOSP 无线调试协议](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md)定义配对二维码格式。

[返回 English ↑](#english) · [简体中文顶部](#chinese)
