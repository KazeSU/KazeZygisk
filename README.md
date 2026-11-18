# KazeZygisk

KazeZygisk is the built-in Zygote injection engine of [KazeSU](https://github.com/KazeSU/KazeSU).
It is implemented via [`ptrace`](https://man7.org/linux/man-pages/man2/ptrace.2.html) and
runs on APatch, KernelSU, and Magisk. It loads both **Magisk Zygisk API** modules and
**Zygisk Next (ZN) API** modules from a single implementation, and can replace Magisk's
built-in Zygisk.

KazeZygisk is a fork of [SukiSU-Nova/BuiltZygisk](https://github.com/SukiSU-Nova/BuiltZygisk)
(NyaZygisk), which is itself a fork of
[JingMatrix/NeoZygisk](https://github.com/JingMatrix/NeoZygisk). The engine keeps NyaZygisk's
dual-API loader, trace hiding and platform coverage, and adds the lifecycle, health and
recovery layer owned by KazeSU's `ksud`. Upstream copyright notices are preserved; see
[NOTICE](NOTICE).

## Why KazeZygisk

There are two distinct module APIs in the Zygisk ecosystem:

* **Magisk Zygisk API** (`zygisk_module_entry`): used by most Zygisk modules, such as LSPosed.
* **Zygisk Next API** (`zn_module`, declared in `zn_modules.txt`): introduced by Zygisk Next after it went closed-source, offering inline / PLT hooking and HyperOS Rust Runtime callbacks.

Before KazeZygisk, running both kinds of modules with open-source software meant stacking two modules: a Zygisk implementation (NeoZygisk or ReZygisk) plus a separate ZN loader (ZNNext). KazeZygisk does both in one GPL-3.0 module.

| | Zygisk Next | **KazeZygisk** | NeoZygisk | ReZygisk | ZNNext |
| :--- | :--- | :--- | :--- | :--- | :--- |
| License | Closed source | **GPL-3.0** | GPL-3.0 | AGPL-3.0 | GPL-3.0 |
| Magisk Zygisk API | ✅ | ✅ v5 | ✅ v5 | ✅ v5 | ❌ |
| Zygisk Next API | ✅ | ✅ v4 | ❌ | ❌ | ✅ v4 |
| HyperOS Runtime API | ✅ | ✅ v1 | ❌ | ❌ | ✅ |
| Both APIs in one module | ✅ | ✅ | ❌ | ❌ | ❌ |

A detailed comparison (in Traditional Chinese) is available at [nkbe.top](https://www.nkbe.top/posts/zygisk-implementations-compare/).

## Features

### Dual API support

* **Magisk Zygisk API v5:** full compatibility with modules built for [Magisk's built-in Zygisk](https://github.com/topjohnwu/Magisk/tree/master/native/src/core/zygisk).
* **Zygisk Next API v4:** loads modules declared in `zn_modules.txt`, providing:
  * `inlineHook` via [Dobby](https://github.com/LSPosed/Dobby) and `pltHook` via [LSPlt](https://github.com/LSPosed/LSPlt);
  * ELF symbol resolution, including `.gnu_debugdata` LZMA decompression for stripped system libraries;
  * companion processes hosted by the root daemon (`kazezygiskd`).
* **HyperOS Runtime API v1:** application callbacks for modules targeting Xiaomi's `hyos_spawner`.

### DenyList and trace hiding

* Clean mount namespaces for apps on the DenyList (see [The DenyList Explained](#the-denylist-explained)).
* Complete removal of injection traces once all Zygisk modules are unloaded, including traces left by the unloading itself.
* Memory map spoofing and CFI shadow handling.
* FD-tracked `TracerPid` sanitization.
* System property spoofing via `spoof.prop` (see [Property Spoofing](#property-spoofing)).

### Platform support

* APatch, KernelSU, and Magisk.
* KernelSU LKM late-load mode and KernelSU emulated soft reboot (temporary root).
* HyperOS `hyos_spawner` runtime injection.
* Android 17 Zygote signatures, including GrapheneOS.
* BTI-enabled devices.
* `riscv64` devices, with ZN inline hooks backed by [rv64hook](https://github.com/eirv/riscv64-inline-hook).

### WebUI

* Real-time status of the daemons and injection.
* Active modules labelled by type (`[Zygisk]` / `[Next]`) with their target process bindings.
* Per-app module exclusion list for user apps.
* Device information, including the vendor ROM version.
* Settings, stored in `/data/system/kazezygisk/config.prop`, that apply to app processes started afterwards (see [Experimental options](#experimental-options)).

### Experimental options

Both options are off by default and can be switched in the WebUI.

* **Anonymous memory** (`anonymous_memory=1`): after specialization, turns the module mappings in `/proc/self/maps` into anonymous mappings. Some users have reported problems with it enabled, such as the system UI failing to start or `Monitor: NO`; if you see that, turn it off first.
* **Custom linker** (`custom_linker=1`): loads modules with KazeZygisk's built-in ELF loader instead of the system linker, so they never enter its solist. If a module cannot be loaded this way, it falls back to the system linker.

## Requirements

| Item | Requirement |
| :--- | :--- |
| Android | 7.1 (API 25) or newer |
| Architecture | `arm64-v8a`, `armeabi-v7a`, `x86_64`, `riscv64` |
| APatch | 10762 or newer |
| KernelSU | kernel 10940 or newer, ksud 11425 or newer |
| Magisk | 26402 or newer, with built-in Zygisk **disabled** |

Install only one Zygisk implementation at a time. KazeZygisk replaces NeoZygisk, ReZygisk, and Zygisk Next; do not install it alongside them.

## Installation

1. Download the latest release from [GitHub Releases](https://github.com/KazeSU/KazeZygisk/releases).
2. Install the zip from your root manager (APatch, KernelSU, or Magisk).
3. Reboot.
4. Check the module description or open the WebUI to confirm the daemons are running.

Use the `release` build for daily use. The `debug` build has verbose logging and should only be used to collect logs for bug reports.


## Official Channel
Telegram: [@KazeKSU](https://t.me/KazeKSU)


## Known Limitations

* **ZN module injection targets:** Zygisk Next and ZNNext can inject ZN modules into any init-spawned process declared with `path=` / `name=` in `zn_modules.txt`. KazeZygisk currently intercepts only Zygote and `hyos_spawner`, so ZN modules targeting other system daemons will not be loaded.

## The DenyList Explained

Modern systemless root solutions operate by creating overlay filesystems using [`mount`](https://man7.org/linux/man-pages/man8/mount.8.html) rather than directly modifying system partitions. The DenyList hides these modifications by controlling the [mount namespace](https://man7.org/linux/man-pages/man7/mount_namespaces.7.html) of each application process.

| Application State | Mount Namespace Visibility | Use Case |
| :--- | :--- | :--- |
| **Granted Root Privileges** | Root solution mounts + module mounts | Trusted apps that require root access (e.g., advanced file managers). |
| **On DenyList** | Clean, unmodified mount namespace | Apps that perform root detection. Root and module mounts are hidden. |

KazeZygisk uses two strategies to provide a clean mount namespace:

1. **Direct Zygote unmounting (primary):**
   KazeZygisk unmounts root-related traces from the Zygote process itself, so the environment is clean *before* the app process is specialized. This only runs after a safety check: if a module provides critical system resources (e.g., an overlay in `/product`), the unmount is aborted to avoid crashing Zygote.

2. **Namespace switching (fallback):**
   If the direct unmount is aborted, or any trace fails to unmount, the forked app process is switched into a cached, clean mount namespace with `setns`.

### Configuration

* **APatch / KernelSU:** enable **`Umount modules`** for the target app.
* **Magisk:** use the **`Configure DenyList`** menu.

> [!IMPORTANT]
> Magisk's **`Enforce DenyList`** option enables Magisk's *own* DenyList, which is separate from KazeZygisk, does not guarantee hiding all mount traces, and may conflict with KazeZygisk. Keep it disabled.

## Property Spoofing

At startup, KazeZygisk reads `/data/adb/modules/kazezygisk/spoof.prop` and overrides the listed system properties in hooked property reads. The default file covers:

* bootloader and verified boot state (`ro.boot.verifiedbootstate`, `ro.boot.vbmeta.device_state`, `ro.boot.flash.locked`, ...);
* build type and debuggable flags;
* vendor-specific properties for MIUI, Realme, and OPlus.

`ro.boot.vbmeta.digest` is generated randomly each time the properties are loaded. Edit `spoof.prop` to add, change, or remove entries; lines starting with `#` are ignored.

## Building

Requirements: JDK 21, Android SDK with NDK `27.2.12479018`, Rust with [`cargo-ndk`](https://github.com/bbqsrc/cargo-ndk).

```sh
./gradlew zipRelease zipDebug
```

The module zips are written to `module/build/outputs/release/`.

## Credits & Acknowledgements

* [NeoZygisk](https://github.com/JingMatrix/NeoZygisk): the original base project
* [Magisk](https://github.com/topjohnwu/Magisk): the foundation of modern Android root and Zygisk
* [ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext): the original Zygisk Next architecture and API
* [ZNNext](https://github.com/VeryBaaad/ZNNext): reference implementation of the standalone Zygisk Next API
* [Dobby](https://github.com/LSPosed/Dobby): inline hooking engine
* [rv64hook](https://github.com/eirv/riscv64-inline-hook): inline hooking engine for RISC-v 64
* [LSPlt](https://github.com/LSPosed/LSPlt): PLT hooking library for Android
* [xz-embedded](https://github.com/tukaani-project/xz-embedded): `.gnu_debugdata` decompression

## License

KazeZygisk is licensed under the [GNU General Public License v3.0](LICENSE).
