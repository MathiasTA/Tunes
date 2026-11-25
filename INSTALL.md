# Installing Tunes

Tunes isn't on the App Store, so it's installed with **SideStore**. SideStore is a free app that installs apps on your iPhone using your own Apple Account. Setting it up takes about 30 minutes and needs a computer once. After that, everything happens on the phone.

**You'll need:**
- An iPhone on **iOS 17 or newer**, with a passcode
- An **Apple Account**
- **Wi-Fi**
- A **computer and USB cable**, for the first setup only. Windows, Mac, Linux or Chromebook all work.

You don't need a GitHub account. This site just hosts the app file.

---

## 1. Set up SideStore (one time)

SideStore's official guide, with screenshots, is at **[docs.sidestore.io](https://docs.sidestore.io)**. If anything here differs from what you see, follow theirs.

**On your iPhone**
1. Install **LocalDevVPN** from the App Store, open it and tap **Connect**. Allow the VPN configuration if asked.
   *It isn't a normal VPN: it just lets SideStore install apps on the phone. It only needs to be on while installing or refreshing apps.*

**On the computer**

2. Download **iloader** from **[iloader.app](https://iloader.app)** or **[its GitHub page](https://github.com/nab138/iloader/releases)**. These are the only official sources.
   - **Windows:** install **iTunes** first. Apple's own download works best.
   - **Linux / Chromebook:** see the extra steps in SideStore's guide.
3. Connect your iPhone with the cable. Tap **Trust** on the phone if asked.
4. Open iloader, sign in with your Apple Account (it's case-sensitive), select your iPhone, and click **Install SideStore (Stable)**.

**Back on your iPhone**

5. Go to **Settings → General → VPN & Device Management**, tap your Apple Account under *Developer App*, and tap **Trust**.
6. Go to **Settings → Privacy & Security → Developer Mode**, and turn it on. The phone restarts.
7. Connect **LocalDevVPN**, open **SideStore** and sign in with the same Apple Account.
8. In **My Apps**, tap the **7 DAYS** button next to SideStore. Accept if it asks about a certificate. The app may close; that means it worked.

## 2. Install Tunes

1. On your iPhone, open **[the latest release](https://github.com/MathiasTA/Tunes/releases/latest)** and tap **Tunes.ipa** under *Assets* to download it.
2. Connect **LocalDevVPN**, open **SideStore → My Apps**, tap **+**, and pick **Tunes.ipa** from Downloads.

Tunes now shows up on your Home Screen.

## 3. Refresh every 7 days

Apps installed with a free Apple Account expire after 7 days unless refreshed. Connect LocalDevVPN, open SideStore → **My Apps**, and tap **Refresh All**. Doing it every few days is plenty.

If Tunes does expire, it just won't open until you refresh it. Nothing is lost.

A free Apple Account can have **3 sideloaded apps** at a time, and SideStore counts as one.

## Updating

Download the newest **Tunes.ipa** from Releases, then install it with **+** in SideStore, like the first time. It replaces the old version and keeps your downloads, playlists and stats. Your current version is shown in Tunes under Settings → About.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| SideStore can't connect to the device | Make sure LocalDevVPN says **Connected** and you're on Wi-Fi. |
| "Untrusted Developer" | Settings → General → VPN & Device Management → your Apple Account → **Trust**. |
| No Developer Mode setting | It only appears after SideStore has been installed from the computer (step 4). |
| Tunes won't open | It needs a refresh (see section 3). |
| SideStore asks for a pairing file | This can happen after an iOS update. Use iloader's pairing file option on a computer, or see the "Pairing file" page in SideStore's guide. |
| iloader doesn't see the iPhone | Unlock the phone, tap **Trust**, and try another cable or port. On Windows, check iTunes is installed. |

For SideStore or iloader problems, see **[docs.sidestore.io](https://docs.sidestore.io)**.

---

### Building it yourself (optional)

Fork this repository, enable Actions, and run **Build IPA**. Your fork's Releases page then gets its own `Tunes.ipa`. No Mac needed.
