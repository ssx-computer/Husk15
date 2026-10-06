# Husk

[![Husk Downloads](https://img.shields.io/github/downloads/leviidev/husk/total?style=for-the-badge&color=5865F2&labelColor=111111)](https://github.com/leviidev/husk/releases)

Android app launcher for iOS.

Drop in an APK, tap it, and the Android app opens full-screen.

## Requirements

The deployment target is **iOS 15.0**. The UI API the app was written against
(`NavigationStack`, `.snappy`, `.topBarTrailing`, `statusBarHidden`, ...) is
16/17+; everything it needs goes through the helpers in
[Compatibility.swift](src/app/Husk/Compatibility.swift), which take the modern
path on iOS 16+ and approximate it on iOS 15:

- `HuskNavStack` / `HuskNavPathStack` -- `NavigationStack` and its value-driven
  form. On iOS 15 the stack is rendered by hand from the same `path` binding,
  so pushing (appending to `path`) and popping (`removeLast()`) read the same
  on both branches. Value-based pushes are buttons that append, so they work
  on both.
- `Animation.huskSnappy` -- `.snappy` (iOS 17) as an equivalent spring.
- `.navigationBarLeading/Trailing` instead of `.topBarLeading/Trailing`
  (iOS 17), which behave the same on every version.
- `huskStatusBarHidden`, `huskPersistentOverlaysHidden`, `huskSheetHeight`,
  `huskToolbarHiddenTabBar`, `huskScrollBackgroundHidden` -- gated forms of the
  iOS 16 modifiers, each with the closest iOS 15 behaviour (the system tab bar
  is hidden globally through `UITabBar.appearance()` on iOS 15, which has no
  per-view way to reach it).

Known gaps on iOS 15, all cosmetic: no GPU-accelerated rendering (the ANGLE
dylib is built for 16.4 -- its Metal pixel-format annotations cannot be
lowered -- and is dlopened, so on iOS 15 GL start-up fails and QemuRunner
falls back to the software display), sheets take the system's default sizing,
the home indicator stays visible, and Form backgrounds keep the system grey.

The built-in StikJIT helper still targets iOS 26+ and falls back to StikDebug
below that; see [docs/06-built-in-jit.md](docs/06-built-in-jit.md).

## JIT

Husk needs JIT, which on iOS takes an attached debugger. Use StikDebug, or
Husk's built-in StikJIT helper (iOS 26+), which on iOS 27 can pair with your
iPhone from Settings with no computer. The app walks you through it; see
[docs/06-built-in-jit.md](docs/06-built-in-jit.md).

## Builds

Every push builds an unsigned `Husk.ipa` in GitHub Actions
([build-ipa.yml](.github/workflows/build-ipa.yml)). It is attached to the run
as an artifact, ready for AltStore, SideStore or TrollStore to sign and
install. The first run builds QEMU and its dependencies from scratch, which
takes a couple of hours; after that they are cached.

## Licence

GPL-2.0-or-later. Husk links QEMU, which is GPLv2, so the shipped binary is a
combined GPLv2 work and the full source is public. It cannot go on the App
Store — both because of that and because it needs `get-task-allow` plus a
debugger attaching at runtime. See [docs/01-licensing.md](docs/01-licensing.md).
