# NotchIsland Media Bridge (browser extension)

Shows what is playing in **YouTube, YouTube Music, Spotify Web, SoundCloud, Deezer and Twitch** inside NotchIsland,
with artwork and play/pause/next/prev controls. Needed because macOS 15.4+ blocks the private MediaRemote API for third-party apps.

## Install (Chrome, Edge, Brave, Arc, Opera)

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → pick this `extension` folder.
3. Play something on YouTube. NotchIsland picks it up within a second (the app listens on `127.0.0.1:47831`).

Firefox: `about:debugging` → *This Firefox* → *Load Temporary Add-on* → `manifest.json`.
Safari needs an Xcode-wrapped extension; not provided.

Nothing leaves your Mac: the extension talks only to `127.0.0.1`.
