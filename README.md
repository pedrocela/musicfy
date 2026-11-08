# Musicfy

A floating player for **Music and Spotify** on macOS. Always in view: above every
window and on every Space, also over full-screen apps. It steps aside while a video plays
in full screen on its display, and comes back when that full screen ends (unless you turn
on "Show Over Full Screen"). It shows whatever is playing in either app.

## Modes

| Mode | Size | What it is |
|---|---|---|
| **Artwork** | 200 to 640, square | Just the artwork. On hover, the controls appear over glass made from the artwork. |
| **Compact** | 320 × 136 | Thumbnail, title, time and controls. The background takes the artwork's color. |
| **Island** | 300 × 44 | A pill at the top center of the screen, tinted like compact. It opens downward on hover. |

- Artwork scales smoothly with its size and shows more as it grows: under 300 only
  Lyrics and Up Next up top and previous, play and next below (shuffle, repeat and
  volume move to the menu); from 300 Audio Output, Volume, shuffle and repeat join;
  from 380 the Compact button too.
- **Resize** artwork from any corner or side. Push its top or bottom edge in to turn it
  into compact; pull any edge or corner of compact out to turn it back into artwork. The
  edge you don't pull stays where it was, with lyrics or Up Next open below too.
- **Drag** artwork or compact to the top center of the screen and let go: it becomes the
  Island. **Pull the Island down** and it becomes the artwork again.
- **Double click** an empty area: switch between artwork and compact.
- **Right click** the player, or click the menu bar icon: the menu (⌘1, ⌘2, ⌘3 pick a mode).
- **⌥⌘M** from any app: show or hide the player.
- The **app glyph** (Music's pink note or Spotify's green disc) shows which app is playing; click it to bring that app to the front.
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
  reads the state every 1.5 s while a song plays on screen (every 4 s when paused or
  hidden). Between reads, Core Animation moves the progress bar and the Island's ring by
  itself, so the app stays idle while music plays.
- Artwork is decoded off the main thread and scaled to the size it's drawn at; the mouse
  is followed 30 times a second only while it moves.
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
