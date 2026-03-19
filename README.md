# EasyShot

Persistent screenshot thumbnails for macOS. When you take a screenshot (Cmd+Shift+4), EasyShot keeps it visible on screen until you use it — no more racing against the 5-second timeout.

## Features

- **Persistent thumbnails** — screenshots stay on screen until you close (X) or drag them
- **Compact card-stack** — multiple screenshots overlap neatly with a count badge
- **Drag & drop** — drag a thumbnail directly into any app (Messages, Slack, Mail, etc.)
- **Multi-monitor** — thumbnails appear on whichever screen your mouse is on
- **Launch at Login** — starts automatically, lives in your menu bar
- **Universal binary** — runs natively on Apple Silicon and Intel Macs

## Install

Download the latest notarized DMG from [Releases](https://github.com/skelpo/easyshot/releases), open it, and drag EasyShot to Applications.

On first launch, EasyShot automatically disables the built-in macOS screenshot thumbnail so captures are instant.

## Build from source

```bash
git clone https://github.com/skelpo/easyshot.git
cd easyshot
./build.sh
open build/EasyShot.app
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## License

Copyright Skelpo GmbH
