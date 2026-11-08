## Install

Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

1. Download **Musicfy.zip** below and double-click it to unzip.
2. Drag **Musicfy** into your **Applications** folder.
3. **Let macOS open it.** Musicfy isn't signed with an Apple developer account, so the first time macOS says it can't be opened. Open **Terminal** (Applications → Utilities), paste this line and press Return:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Musicfy.app
   ```

   Without Terminal: open Musicfy once and close the warning, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. The Terminal line is the better option: it also lets Musicfy read Podcasts.
4. **Open Musicfy** from Applications. It lives in the menu bar at the top of the screen, not in the Dock.
5. **Allow it to control Music and Spotify.** When macOS asks whether Musicfy may control Music or Spotify, click **Allow**. If you clicked Don't Allow by mistake: System Settings → Privacy & Security → Automation → Musicfy, and turn both on.

To start it automatically: click its icon in the menu bar → **Open at Login**.

## Update

Download the new Musicfy.zip, quit Musicfy, replace the app in Applications and run the Terminal line from step 3 again.
