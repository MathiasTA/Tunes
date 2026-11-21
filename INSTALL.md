# Installing Tunes on your iPhone

Tunes isn't on the App Store. You install it yourself with **SideStore**, a free app that signs apps with your own Apple Account. You need a computer once, to set up SideStore. After that, everything happens on the iPhone.

## What you need

- An iPhone with **iOS 17 or newer** and a passcode set
- An **Apple Account** (the free one is fine)
- **Wi-Fi**
- A **computer** for the first setup only (Windows, Mac, Linux or a Chromebook)

## Step 1: Set up SideStore (one time, with a computer)

Follow the official guide at **https://docs.sidestore.io**. In short:

1. Install **LocalDevVPN** from the App Store on your iPhone.
2. On your computer, download **iloader** from the SideStore guide and use it to install SideStore on your iPhone. On Windows you also need iTunes, downloaded from Apple's website.
3. Open SideStore on your iPhone and sign in with your Apple Account.

If iOS asks you to turn on **Developer Mode**, go to **Settings → Privacy & Security → Developer Mode**, turn it on, and restart the iPhone.

If something goes wrong here, the SideStore guide and its community are the best places to get help. This part has nothing to do with Tunes.

## Step 2: Download Tunes

1. On your iPhone, open this repository's **Releases** page in Safari. It's in the right-hand column on GitHub, or add `/releases` to the end of the repository address.
2. Under the newest release, tap **Tunes.ipa**.
3. Tap **Download**. The file is saved to the Files app, in Downloads.

## Step 3: Install it with SideStore

1. Open **LocalDevVPN** and connect.
2. Open **SideStore** and go to the **My Apps** tab.
3. Tap **+** in the top corner.
4. Pick **Tunes.ipa** from Downloads.
5. Wait until Tunes appears in the list. Then open it from your Home Screen.

If iOS says **"Untrusted Developer"**, go to **Settings → General → VPN & Device Management**, tap your Apple Account, and tap **Trust**.

## Step 4: Keep it working

Apps installed with a free Apple Account stop opening after **7 days** unless they're refreshed.

- Every few days, connect **LocalDevVPN**, open **SideStore**, and tap **Refresh All**.
- If Tunes has already stopped opening, do the same thing. Your music, playlists and stats are kept.

## Updating to a new version

1. Download the newest **Tunes.ipa** from Releases, the same way as in step 2.
2. In SideStore, tap **+** and pick the new file. It installs over the old version.

Your downloaded songs, playlists, likes and stats stay.

## Getting started in the app

- **Search** from the bar on Home. Tap a song to hear a preview, or the arrow to download it.
- Downloaded songs play offline and stay linked to the real artist, so your stats and Wrapped are accurate.
- **Import from Spotify:** Library → Create / import playlist → Import from Spotify, then paste a public playlist link.
- **Shows near you** on artist pages are optional. They need a free key from developer.ticketmaster.com, pasted in Settings → Connections.

## Building your own copy (optional)

You don't need a Mac. GitHub builds the app for you.

1. **Fork** this repository on GitHub.
2. In your fork, open the **Actions** tab and turn on workflows.
3. Open **Build IPA → Run workflow**. A build takes about 10 minutes.
4. When it's done, your fork's **Releases** page has a fresh **Tunes.ipa**. Install it as in step 3.
