# 🎵 Tunes

**A music app for iPhone that's yours.** Search any song or artist, download music to play offline, and every song stays linked to the real artist and album. So your stats, top artists and Wrapped are actually accurate.

### 👉 [How to install Tunes (step-by-step guide)](INSTALL.md)

### 📲 [Download the latest version](https://github.com/MathiasTA/Tunes/releases/latest)

Free. No account. No ads. Everything stays on your phone.

---

## Features

### 🔎 Search & discover
- Search songs, artists and albums; your own downloads show up first
- Tap any song to hear a **30-second preview** before downloading
- Recent searches remembered
- Search bar on Home that slides to the top as you tap it
- **Charts** from countries around the world, genres and editors' picks, which you can add to Home
- **Trending** songs and **new releases**
- Artist pages with **popular songs**, the **full discography**, **similar artists**, **upcoming shows near you** and a **bio**
- **Discography page** you can filter by **Albums**, **Singles & EPs** or **Features**, and sort newest or oldest first. It also finds releases the catalog's own lists sometimes miss.
- **Follow** artists

### ⬇️ Downloads
- Download single songs, whole albums or whole playlists
- Downloaded songs keep the **real cover, artist and album**
- **Best** or **space-saving** quality
- **Download progress** everywhere: a bar above the player, a card in Library, and inside each album or playlist
- **Downloads screen** listing everything in progress, plus retry or clear failed downloads
- **Fix download** screen for a song that won't download: see what went wrong, pick a different YouTube version (with matching lengths highlighted), paste a link, or use your own file
- Option to download only on Wi-Fi
- Storage limit, plus automatic removal of songs you haven't played in 3 months

### ▶️ Player
- Play, pause, skip, scrub, **shuffle** and **repeat** (all or one)
- Full-screen player with a background from the cover's color, a blurred cover, or plain
- Tap the song title to open its album, or the artist name to open the artist
- **Queue**: see what's next, reorder, remove, and save the queue as a playlist
- **Sleep timer** (minutes, or end of song)
- **Synced lyrics** that follow the music, with timing adjustment
- **Music videos** (with a warning on mobile data)
- Play on **AirPods, Bluetooth speakers and AirPlay** devices
- Lock Screen and Control Center controls
- **Swipe** a song right to add it to the queue, or left to like it
- Like songs; they all collect in **Liked songs**

### 🎚️ Sound
- **10-band equalizer** with presets, plus your own custom settings
- A separate sound setting for **iPhone speaker, headphones and speakers**, switching automatically
- **Volume leveling**, so loud and quiet songs play at a similar volume
- **True gapless playback**, so albums with songs that run into each other play without a pause
- **Crossfade** (0–12 seconds), with an option to never crossfade inside albums

### 📚 Library & playlists
- Playlists, Songs and Artists, with sorting, filters and **pinning**
- **Create your own playlists**, with your own **cover photo**
- **Search inside** any album, playlist or Liked songs
- **Auto playlists** that update themselves:
  - **Daily mixes** built around your top artists, new every day
  - New releases from your artists
  - Your most played
  - Forgotten favorites
  - Artists similar to yours
  - Any chart
  - Each with adjustable rules and size
- **Import Spotify playlists** with a link (up to 100 songs) or a CSV file (any size). Songs are matched to the real versions, and you can fix the ones it wasn't sure about.
- **Export playlists** as a CSV file or as text
- **Import songs** that aren't in the catalog, **from YouTube** or **from files on your phone**, and link them to the real artist so they count in your stats
- **Edit any song**: title, album, cover, linked artists (including features), which YouTube version it uses, trim the start and end, and fade in/out

### 📊 Stats & Wrapped
- Listening time, plays, top artists, top songs and top genres, for the last 7 days, 30 days, year or all time
- Charts of your listening over time, plus stats for each song
- **Wrapped**: an animated story of your year (or month, or all time):
  - Minutes listened, your biggest day, and a quiz on your #1 song
  - Top artist, top songs, genres, new discoveries, your listening clock, your listening personality, a time machine and your longest streak
  - Each slide plays a fitting song
- **Share card** for your Wrapped, with themes and your own colors, patterns, fonts, layouts, info to show, and sizes for stories, posts or square
- **Import your Spotify listening history** so your stats go back years

### 🏠 Home
- A greeting with your name, plus quick access to your profile
- Sections you can **turn on or off and reorder**:
  - Listening summary
  - Made for you
  - New from your artists
  - Charts
  - Recently played
  - Recently downloaded
  - Your top artists
  - Following
  - On repeat
  - Trending
  - New releases
  - Your playlists
  - Your favorite albums right now
- **Each section has its own layout**: big covers, small covers, featured, compact grid, cover grid, list or numbered list
- **Each section's size**: choose how many items it shows

### 🎨 Look & feel
- **Themes**:
  - Plain: **Dark**, **Black** (pure black for OLED screens), **Light** and **Auto**
  - Gradient: **Midnight**, **Sunset**, **Ocean**, **Forest** and **Rosé**
  - Animated, with slowly drifting light: **Aurora**, **Nebula** (with twinkling stars), **Lava**, **Lagoon** and **Pastel**
- **8 accent colors**, and **12 app icons**
- Corner roundness, cover shape and text size
- Tab bar labels, haptics and animations can be switched on or off

### 👤 Profile & privacy
- Your name and photo
- **Private listening**: off, 1 hour, 8 hours, until tomorrow, or always. You can also keep it out of your stats.
- **Offline mode**: shows only what's downloaded

### 💾 Backup
- Back up to **iCloud Drive** or your iPhone, automatically on Wi-Fi (daily or weekly)
- Keep several backups, and restore any of them
- Includes your playlists, likes, stats, settings, your pictures, and songs you imported yourself

### 🔗 Sharing
- Share any song with a link that opens in whatever music app your friend uses, or with a link for a specific app

---

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
