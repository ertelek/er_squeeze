# Squeeze!

_A fast, reliable way to **shrink large videos** on your phone._  
Choose **All folders** or **Selected folders**, then let it run in the background. Pause or resume anytime. See clear progress per folder.

- **Space saver**: re-encodes to efficient formats to free GBs.  
- **Flexible scope**: scan entire internal storage or only the folders you pick.  
- **Safe by design**: you decide whether to **keep originals** (with a suffix) or **replace** them.

---

## Why would I want this?

Phones fill up—especially with 4K/60fps video. Squeeze! converts those files to more compact versions while keeping good quality, so you can reclaim space without hunting through every folder manually.

For very large videos, compression can take **many hours or even days**. That’s expected — Squeeze! is built to chug along in the background and pick up where it left off.

---

## Install / Build

This is a Flutter app. You can run it locally or build release APK/AABs.

**Prereqs**
- Flutter 3.19+ (`flutter --version`)
- Android SDK + Android Studio (for platform tools & emulators)
- Java 17 (recommended for modern Gradle)
- A real device or emulator

**Run in debug**
```bash
flutter pub get
flutter run
```

---

## Quick Start (2 minutes)

1) **Choose scope**
   - **All folders** – scans the whole internal storage. Originals are replaced after success.
   - **Selected folders** – add only the folders you want. You can keep originals (with a suffix) or replace them.

2) **Set options**
   - **Keep original files**: If ON, enter a **Compressed file suffix** (e.g., `_small`).  
     If OFF, Squeeze replaces the original after a successful encode.

3) **Grant permissions (Android)**
   - Tap **Permissions → All files access** so Squeeze can scan/write across storage.

4) **Start**
   - Tap **Start compression**. You can **Pause** or **Resume** anytime from the Status tab.

> If your phone stops the background service to save power (e.g., low battery), **open the app again** to continue. Progress is saved.

---

## Core ideas

- **Two safe workflows**  
  - _Keep originals_: new files are created with a suffix; originals remain.  
  - _Replace originals_: originals are moved/removed only after a successful encode.

- **Background friendly**  
  Runs under a foreground notification on Android. If the OS suspends the process, reopen Squeeze and it resumes.

- **Progress status**  
  Each folder shows percent done, current file, and completion state.

---

## Everyday workflows

### Free space everywhere
- Enable **All folders**, Start, leave the phone plugged in.  
- Check back later; large libraries may take **hours to days**.

### Free space in one folder (e.g., Camera)
- Switch to **Selected folders**, pick `DCIM/Camera`, uncheck **Keep original files** to reclaim space aggressively.

### Keep originals for safety
- Switch to **Selected folders**, check **Keep original files**, set a suffix like `_min`.  
- Compare quality later, then manually delete originals if you’re happy.

---

## Permissions (Android)

- **All files access** (MANAGE_EXTERNAL_STORAGE): lets Squeeze scan and save videos across internal storage—needed for “All folders” and most selected folders.
- **Notifications**: shows progress while encoding.

> iOS-style full-device scanning isn’t supported on iOS; this project currently targets Android.

---

## Important notes for first-time users

- **Time expectations**: big libraries = **many hours or days**. That’s normal.
- **Battery & heat**: video encoding is CPU/GPU heavy. Plug in your phone; slight warmth is expected.
- **Background limits**: some devices kill long-running work on low battery or strict power modes. If work stops, **reopen the app** to resume.
- **Free space**: keep extra storage available for temporary files during conversion.
- **Your data stays local**: Squeeze does **not** upload videos. Everything happens on your device.

---

## Troubleshooting

- **“Start” is disabled** in Selected folders mode  
  → If “Keep original files” is ON, you must set a **suffix** (e.g., `_small`). Also add at least one folder.
- **Nothing happens after tapping Start**  
  → Grant **All files access** in Permissions. Some OEMs require you to turn off battery optimizations.
- **Service stopped overnight**  
  → Reopen Squeeze; it resumes where it left off.
- **Not enough space**  
  → Free some space first; encoders may need temporary room.

---

## Contributing

Issues and pull requests are welcome. Please include:
- Device model + Android version
- Steps to reproduce
- Logs (if available)

---

## Privacy

Squeeze! processes videos **only on your device**. No analytics or uploads by default. See the [`Privacy Policy`](./privacy.md) in this repo.

---

## License

GPLv3 — see [`LICENSE`](./LICENSE).
