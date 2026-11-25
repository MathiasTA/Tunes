# 🎵 Tunes

**A music app for iPhone that's yours.** Search any song or artist, download music to play offline, and every song stays linked to the real artist and album. So your stats, top artists and Wrapped are actually accurate.

### 👉 [How to install Tunes (step-by-step guide)](INSTALL.md)

### 📲 [Download the latest version](https://github.com/MathiasTA/Tunes/releases/latest)

Free. No account. No ads. Everything stays on your phone.

---

## Features

**Your music, properly linked**
- Search any song, artist or album and preview it before downloading
- Downloads play offline and keep the real cover, artist and album
- Every play counts for the right artist, even songs you import yourself from YouTube or your own files

**Discover**
- Charts from around the world, trending songs and new releases
- Artist pages with popular songs, full discography, similar artists, upcoming shows and a bio
- Daily mixes and other auto playlists that update themselves, like new releases from your artists, most played, forgotten favorites and similar artists

**Playlists**
- Make your own, with your own cover photos
- Import playlists from Spotify. Songs are matched to the real versions.
- Export playlists to share them

**Listening**
- Synced lyrics
- Music videos
- Queue, shuffle, repeat and sleep timer
- AirPods, Bluetooth and AirPlay
- 10-band equalizer, with separate sound for your phone speaker, headphones and speakers
- Volume leveling, true gapless playback and crossfade

**Stats & Wrapped**
- Your top artists, songs, genres and listening time, for any period
- An animated Wrapped, with music playing along and a quiz on your #1 song
- A shareable Wrapped card you can design yourself
- Import your Spotify history, so your stats go back years

**Make it yours**
- A Home screen you arrange yourself: pick which sections show, in what order, and how each one looks
- Player styles, including a vinyl record you can spin back by hand, a cassette with turning reels, and a lyrics-first player
- Progress bar and mini player styles, fonts, and any accent color
- Over 20 themes, including animated ones, **Dynamic** (colors from the song that's playing) and **Horizon** (follows the sky from sunrise to night)
- Playlist covers: your own photo, album collages, gradients or emoji
- 12 app icons
- Badges to earn in bronze, silver and gold, which you can show off on your Home screen
- Private listening, offline mode and automatic backups to iCloud Drive

## Where the music comes from

| What | From |
|---|---|
| Song, artist and album info, charts and covers | Deezer |
| Audio and music videos | YouTube |
| Lyrics | LRCLIB |
| Artist bios | Wikipedia |
| Upcoming shows | Ticketmaster (optional, needs a free key you add in Settings → Connections) |

There's no Tunes server. Everything runs on your iPhone.

## Good to know

- Tunes is a personal project, not in the App Store, and it comes with no guarantees.
- Downloads depend on YouTube. If YouTube changes something, downloads can stop working until Tunes is updated.
- Brand-new songs sometimes reach Spotify a few days before they're in Tunes' catalog. Until then, you can import them from YouTube.
- Music videos play in standard quality.
- Google Home and Nest speakers work over Bluetooth after pairing them in the Google Home app.

---

<details>
<summary>For developers</summary>

SwiftUI app for iOS 17+. The Xcode project is generated with XcodeGen, and GitHub Actions builds an unsigned `.ipa` on every push to `main`, published under Releases as version `1.<build number>`.

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
</details>
