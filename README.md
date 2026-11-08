# Musicfy

A floating player for **Music and Spotify** on macOS. Always in view: above every
window, on every Space and over full-screen apps too. It shows whatever is playing
in either app.

## Modes

| Mode | Size | What it is |
|---|---|---|
| **Artwork** | 200 to 640, square | Just the artwork. On hover, the controls appear over glass made from the artwork. |
| **Compact** | 320 × 136 | Thumbnail, title, time and controls. The background takes the artwork's color. |
| **Island** | 300 × 44 | A pill at the top center of the screen. It opens downward on hover. |

- Small artwork shows less: under 300 the chip turns into a dot and the audio output and
  mode buttons step aside; under 250 only lyrics and volume stay up top, and the times
  appear when you point at the bar. Everything is still in the menu.
- **Resize** artwork from any corner or side. Push its top or bottom edge in to turn it
  into compact; pull compact's bottom or sides out to turn it back into artwork.
- **Drag** artwork or compact to the top center of the screen and let go: it becomes the
  Island. **Pull the Island down** and it becomes the artwork again.
- **Double click** an empty area: switch between artwork and compact.
- **Right click** the player, or click the menu bar icon: the menu (⌘1, ⌘2, ⌘3 pick a mode).
- **⌥⌘M** from any app: show or hide the player.
- Click the **app chip** (● Music / ● Spotify) to bring that app to the front.
- When nothing plays, artwork shrinks to compact and comes back when music starts
  (turn it off with "Shrink When Paused").

At the top: synced **lyrics** (from [LRCLIB](https://lrclib.net)), **Up Next**, the app's
**volume** and the Mac's **audio output**. Choose which ones show in "Show Buttons".

## Install

Requires macOS 14 or later and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/pedrocela/musicfy.git
cd musicfy
./build.sh --install
```

The first time, macOS asks whether Musicfy may control Music and Spotify: allow it.
If it was denied by mistake: System Settings → Privacy & Security → Automation → Musicfy.

To start it automatically: menu → "Open at Login".

## How it works

- It reads and controls the apps with **AppleScript** (the only thing Music and Spotify
  allow from outside). It never launches them: every script first checks that the app
  is running. Commands jump ahead of state reads, so buttons respond right away.
- It hears about changes instantly through the notifications both apps post, and also
  reads the state every 1.5 s. The progress bar is interpolated between reads.
- If Music doesn't provide the artwork (Apple Music songs not in the library), it looks
  it up in the public iTunes catalog.
- The glass in artwork mode is computed with Core Image from the artwork itself: a
  progressive blur under the controls and a frosted copy behind the capsules.

## Code

```
Sources/Musicfy/
  App/      floating window, menu bar, menus, modes, resizing and mouse
  Engine/   Music and Spotify, state, artwork, glass, colors, lyrics, audio output
  UI/       SwiftUI views; Theme.swift holds sizes, colors and motion
```
