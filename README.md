# Tunes

A personal music app for iPhone. Search for any song or artist, play previews, and download songs to listen to offline. Every download stays linked to its real artist and album, so your listening stats and your Wrapped are accurate.

**To install it, see [INSTALL.md](INSTALL.md).**

## What it does

- **Search and download** songs, albums and artists. Downloads play offline.
- **Home** with charts, trending songs, new releases and your own listening, which you can rearrange.
- **Playlists:** your own, ones imported from Spotify, auto playlists that update themselves, and country and genre charts.
- **Player** with queue, shuffle, repeat, sleep timer, synced lyrics, AirPlay and Bluetooth, an equalizer, volume leveling, gapless playback and crossfade.
- **Artist pages** with popular songs, the full discography, similar artists, upcoming shows and a bio.
- **Stats and Wrapped:** listening time, top artists and songs, and an animated Wrapped with a shareable card.
- **Your own files:** import audio files from your phone and link them to the real artist.
- **Backups** to iCloud Drive or your iPhone, and import of your Spotify listening history.
- **Looks:** themes (Dark, Black, Light, Auto), accent colors, 12 app icons, and more.

## Where things come from

| What | Source |
|---|---|
| Songs, artists, albums, charts and covers | Deezer's public catalog |
| Audio and music videos | YouTube |
| Lyrics | LRCLIB |
| Artist bios | Wikipedia |
| Upcoming shows | Ticketmaster (optional, needs your own free key) |

Nothing is sent to any server of ours. There isn't one. Everything runs on your iPhone.

## Good to know

- Tunes is a personal project, not on the App Store, and it comes with no guarantees.
- Downloads depend on YouTube. If YouTube changes something, downloads can stop working until the app is updated.
- Music videos stream in standard quality and aren't saved.
- Google Home and Nest speakers work over Bluetooth after you pair them in the Google Home app.

## For developers

The app is SwiftUI (iOS 17+). The Xcode project is generated with XcodeGen, and GitHub Actions builds an unsigned `.ipa` on every push to `main`. You can find it under Releases.

```
ios/project.yml            XcodeGen spec
ios/Tunes/App              App entry, root view, navigation
ios/Tunes/Core             Models, settings, storage, network status
ios/Tunes/Services         Catalog, YouTube, lyrics, charts, imports, audio analysis
ios/Tunes/Stores           Library, playlists, stats, backups
ios/Tunes/Playback         Audio engine (gapless, crossfade, EQ) and player
ios/Tunes/UI               Every screen
ios/Tunes/Assets.xcassets  App icons and colors
```
