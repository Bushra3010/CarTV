# Recon map: CarTV – M3U IPTV Player & Cast (iOS, iPhone)

Scope: the core loop: add your own playlist, browse channels by group, play the stream, send it to the car screen. Also car mode, favourites, resume and the mini player. Xtream and Jellyfin come second. Plex, Emby, ReplayKit full-screen mirroring and rotary-knob input come later.
For: the user's own product (rebranded "Backseat").
Date: 2026-11-07

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | App Store listing (IN) | https://apps.apple.com/in/app/cartv-m3u-iptv-player-cast/id6800211040 | description, IAPs, version history, reviews, privacy labels |
| 2 | marketing site | https://cartv.app | not read yet |

## Core loop

Paste or scan an M3U URL, pick a channel from its groups, and watch it on the car display through AirPlay or mirroring, with large passenger-friendly controls.

## Screens

| ID | screen | how to reach | purpose | key components | states |
| --- | --- | --- | --- | --- | --- |
| S01 | Home | tab 1 | recently played, continue watching, favourites, search with voice search and history | search bar, horizontal rails, channel cards | empty (no playlists), filled |
| S02 | Playlists | tab 2 | list of sources (M3U URL, Xtream, Jellyfin/Emby/Plex, local files) | list rows, swipe actions (refresh, rename, delete), + button | empty, loading, error, filled |
| S03 | Add source sheet | + on S02 | choose a type, then enter URL, credentials or a QR code | segmented type picker, text fields, QR scanner | validating, invalid URL, network error |
| S04 | Channel browser | tap a playlist | channels filtered by group-title, with tvg-logo | group chips, searchable list, favourite star | empty group, filled |
| S05 | Player | tap a channel | full-screen AVPlayer, track selection, AirPlay button, previous and next channel | video, controls overlay, AirPlay route picker, subtitle and audio menu | buffering, playing, error, PiP |
| S06 | Car mode | toggle in S05 or tab | landscape, very large controls, one-tap switch between channels | big buttons, big channel grid | playing, no AirPlay |
| S07 | Cast to Car | tab 3 | how to connect and start AirPlay or mirroring, with hints | route picker, steps, broadcast picker | not connected, connected |
| S08 | Media server library | tap a server source | libraries, then seasons, then episodes | grid, sorted episode list | auth error, empty library |
| S09 | Mini player | while browsing | keeps the video playing in a bar | thumbnail, play/pause, close | |
| S10 | Settings | tab 4 | paywall, restore purchases, FAQ, disclaimer, visualizer style | list | |
| S11 | Paywall | gated feature | weekly, yearly and lifetime plans | plan cards | |

## Flows

```
F01 Add an M3U and watch a channel
    S02 -> S03 (paste URL) -> S04 -> S05
    happy path taps: 5
    edge: invalid URL, HTTP 4xx, huge playlist (50k entries), no group-title, dead stream
F02 Send to the car screen
    S05 -> AirPlay button -> pick the car or receiver
    edge: no receiver found, iOS update breaks casting (top complaint in reviews)
F03 Car mode quick switch
    S05 -> car mode -> tap the next channel
F04 Resume
    S01 continue watching -> S05 seeks to the saved position
F05 Favourite a channel
    S04 star -> S01 favourites rail
F06 Connect Jellyfin
    S03 (server URL, user, password) -> S08 -> S05
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| ChannelRow | list, grid card, big (car) | default, playing, favourite | S01 S04 S06 |
| GroupChips | | selected | S04 |
| SourceRow | m3u, xtream, server, local | loading, error | S02 |
| PlayerControls | normal, car | playing, paused, buffering | S05 S06 |
| MiniPlayer | | | S09 |
| AirPlayButton | | | S05 S06 S07 |

## Inferred data model

```
Source     id, kind (m3u|xtream|jellyfin|emby|plex|local), name, url, username?, password?, addedAt, lastRefreshed
           evidence: description "add by URL or QR, refresh, rename, remove"; v1.0.9 Xtream; v1.1.0 Plex   confidence: high
Channel    id, sourceId, name, streamURL, logoURL (tvg-logo), group (group-title), tvgId
           evidence: description "reads tvg-logo and group-title"   confidence: high
Favorite   channelKey, order          evidence: v1.1.4 manual sorting of favourites   confidence: high
PlaybackPosition  channelKey, seconds, updatedAt   evidence: "remembers where you left off"   confidence: high
SearchHistory     term, at            evidence: v1.1.3   confidence: high
```
All of it is stored on the device. There are no accounts.

## Feature matrix

See `features.csv`.

## Out of scope

- Content: the app supplies none, and neither will the clone.
- Full-screen mirroring of other apps needs a ReplayKit broadcast extension and a receiver. Phase 2.
- Rotary-knob input on car head units depends on the hardware.
- The App Store paywall needs a real App Store Connect product. It is stubbed for now.

## Size

Screens 11, flows 6, entities 5. Hard parts: AirPlay casting reliability, MKV/HEVC/DTS software decode (AVPlayer cannot do it; it needs VLCKit or FFmpeg), and the Jellyfin, Emby and Plex APIs. Size: M.
