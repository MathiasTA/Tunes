# Tunes

A personal music app for iPhone. Search any song or artist, play previews, download songs, and keep every download linked to its real artist and album, so your stats and Wrapped are accurate.

No server and no Mac needed. GitHub builds the app, and SideStore installs it on your iPhone.

## Getting the app

1. Push this folder to a GitHub repository (public is fine; there are no secrets in it).
2. Open **Actions → Build IPA**. It runs on every push, and you can also start it by hand with **Run workflow**. It takes about 10 minutes.
3. When it's green, open **Releases** and download `Tunes.ipa` on your iPhone.
4. In SideStore, tap **My Apps → +** and pick `Tunes.ipa`.

A failed build doesn't cost a sideload slot. Only installing in SideStore counts. If a build fails, the error list is under the failed step's **Errors** group.

### Updating

Push a change, wait for the new release, and install the new `Tunes.ipa` over the old one in SideStore. Your music, playlists and stats stay.

## Where things come from

| What | Source |
|---|---|
| Songs, artists, albums, charts, covers | Deezer public API (no key) |
| Chart fallback | Apple Music RSS |
| Audio and video | YouTube, through YouTubeKit, on the phone |
| Lyrics | LRCLIB |
| Artist bios | Wikipedia |
| Shows near you | Ticketmaster Discovery API. Add your own key in Settings → Connections; it never goes in this repo |
| Share links | song.link |

## Good to know

- **Discord and Last.fm** appear in Connections as "coming later". They need a sign-in flow that isn't in this version.
- **Google Home / Nest speakers**: pair them over Bluetooth in the Google Home app first. Tunes plays to Bluetooth and AirPlay devices, but not Google Cast.
- **Videos** stream at standard quality (about 360p) and are never saved.
- **SideStore** apps need refreshing every 7 days, which SideStore does from the phone.
- If YouTube changes something and downloads stop working, turn on **Settings → Advanced → Backup download method**, or update YouTubeKit by bumping its version in `ios/project.yml`.

## Project layout

```
ios/project.yml          XcodeGen spec (the Xcode project is generated in CI)
ios/Tunes/App            App entry, root view, navigation
ios/Tunes/Core           Models, settings, storage, network status
ios/Tunes/Services       Deezer, YouTube, lyrics, charts, Spotify import, audio analysis
ios/Tunes/Stores         Library, playlists, stats, backups
ios/Tunes/Playback       Audio engine (gapless, crossfade, EQ), player, Wrapped audio
ios/Tunes/UI             Every screen
ios/Tunes/Assets.xcassets App icons (12) and colors
```
