# Backseat — IPTV player and car casting for iPhone

A clean-room rebuild of the core features of an M3U/IPTV player with car casting. SwiftUI, iOS 18+, no third-party dependencies. The app ships no content: users add their own playlists and servers.

## Website (Netlify)

`web/` is a static site with no build step. Netlify publishes it using `netlify.toml`:

- `/` is the web player, laid out like the iPhone app: Home, Playlists, Cast to Car and Settings tabs, a bottom tab bar on phones, and installable to the home screen. Add an M3U link or file, browse channels, play HLS (hls.js, falling back to the browser's own HLS), favourites, resume, car mode and the audio visualizer. Many IPTV servers block browsers (CORS), and https pages can't play `http://` streams, so some playlists only work in the iPhone app.
- `/about/` is the landing page, with `/privacy/` and `/support/` (App Store Connect needs both URLs). The old `/app/` address redirects to `/`.

To preview locally:

```bash
python3 -m http.server 8787 --directory web
```

## Run the iPhone app

Open `Backseat.xcodeproj` in Xcode 26, pick an iPhone simulator, and press Run. To use it on a device, set your Team under Signing.

## Testing purchases

Run from Xcode: the shared scheme loads `Support/Backseat.storekit`, so plans and test purchases work in the simulator. Before release, create products with the same IDs in App Store Connect: `app.backseat.pro.weekly`, `app.backseat.pro.yearly` and `app.backseat.pro.lifetime`.

## What's in it

- **Sources:** M3U/M3U8 URLs (group-title, tvg-logo, #EXTGRP, single HLS URLs), Xtream Codes (live and movies), Jellyfin/Emby (libraries → seasons → episodes, HLS transcode), and local video import.
- **Player:** AVPlayerViewController with PiP, subtitle and audio tracks, and AirPlay. Previous/next through the current list, an up-next queue, resume position, background audio, and lock-screen controls.
- **Car mode:** landscape layout with oversized buttons, ±30 s skip, and a one-tap channel strip.
- **Library:** Home with continue watching, recents and reorderable favourites, global search with history, and a mini player.
- **Extras:** add a playlist by scanning a QR code (camera, or a QR image from Photos). Xtream links fill in the login. Voice search on Home. An audio visualizer for radio and other audio-only streams.
- **Backseat Pro (StoreKit 2):** weekly, yearly (3-day trial) and lifetime plans. Pro unlocks car mode, more than 2 playlists, and the Wave and Rings visualizer styles. Change what's gated in `Backseat/Services/Purchases.swift` (`Entitlements`).
- **Privacy:** everything is stored on the device (Application Support JSON). Passwords and tokens are kept in the Keychain.

`replica/` holds the recon map and feature matrix.
