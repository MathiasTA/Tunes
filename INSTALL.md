# How to install Tunes on your iPhone

This guide assumes you've never done this before. Follow it from top to bottom and you'll be fine. Set aside about **30–45 minutes** the first time. After that, updating takes a minute.

---

## First, what's going on?

Tunes isn't in the App Store, so you can't just tap "Get". Instead you install it yourself, which is called **sideloading**. It's allowed by Apple and doesn't harm your phone.

To do it, you use a free app called **SideStore**. SideStore is like a tiny App Store on your phone that installs apps you've downloaded yourself. It uses your own Apple Account to do it.

The order of things:

1. **Install SideStore** (once). This is the only part that needs a computer.
2. **Download Tunes** to your iPhone.
3. **Install Tunes** using SideStore.
4. **Refresh it now and then**, so it keeps opening.

> 💡 **About GitHub:** This page is on a website called GitHub. It's just where the app's files are kept. You don't need an account, and you don't need to understand anything else on the site.

---

## What you need

- ✅ **An iPhone** with iOS 17 or newer. Check in **Settings → General → About → iOS Version**.
- ✅ **A passcode on your iPhone** (the code you unlock it with).
- ✅ **Your Apple Account** email and password (the one you use for the App Store).
- ✅ **Wi-Fi.** Mobile data doesn't work for installing.
- ✅ **A computer, only for Part 1.** Windows, Mac, Linux or a Chromebook. It can be a friend's computer.
- ✅ **The cable** you charge your iPhone with, to connect it to the computer.

---

## Part 1: Install SideStore (one time only, needs a computer)

SideStore has its own official guide with pictures: **https://docs.sidestore.io**. If anything below doesn't match what you see, follow theirs. Here's the short version.

### 1. On your iPhone: get LocalDevVPN

1. Open the **App Store**, search for **LocalDevVPN** and install it. It's free.
2. Open it and tap **Connect**.
3. If your iPhone asks to **"Add VPN Configurations"**, tap **Allow** and enter your passcode.

> 💡 LocalDevVPN isn't a normal VPN. It doesn't hide your location or slow your internet. It just lets SideStore talk to your iPhone. You only need it switched on while installing or refreshing apps.

### 2. On the computer: get iloader

iloader is the program that puts SideStore on your phone. Only download it from **https://iloader.app** or **https://github.com/nab138/iloader**. Those are the official places.

- **Windows:** first install **iTunes**. The version from Apple's website works best; the Microsoft Store one also works. Then download and run the iloader installer (the **.msi** file).
- **Mac:** download the **.dmg** file, open it and drag iloader into Applications.
- **Linux / Chromebook:** follow the steps on https://docs.sidestore.io (Installation → Prerequisites).

### 3. Install SideStore

1. Plug your iPhone into the computer with the cable.
2. If your iPhone asks **"Trust This Computer?"**, tap **Trust** and enter your passcode.
3. Open **iloader** on the computer.
4. Sign in with your **Apple Account**. Type the email exactly; capital letters matter.
5. Pick your iPhone from the list.
6. Click **Install SideStore (Stable)** and wait until it says it's done.

You can unplug the phone now. **You won't need the computer again.**

### 4. On your iPhone: allow SideStore to open

1. Open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your Apple Account email.
3. Tap **Trust "…"**, then **Allow & Restart** if asked, and enter your passcode.
4. Go to **Settings → Privacy & Security**, scroll to the very bottom, and turn on **Developer Mode**. Your iPhone restarts. After it restarts, tap **Turn On** if it asks.

### 5. Finish setting up SideStore

1. Open **LocalDevVPN** and tap **Connect**.
2. Open **SideStore** and sign in with the **same Apple Account** you used in iloader.
3. Tap the **My Apps** tab at the bottom.
4. Next to SideStore, tap the button that says **7 DAYS**.
5. If it asks about a certificate, tap **Yes** or **Refresh Now**.

Your phone might jump back to the Home Screen. That's normal and means it worked.

🎉 **SideStore is installed.** The hard part is over.

---

## Part 2: Download Tunes (on your iPhone)

1. On your iPhone, open **Safari** and go to:

   **https://github.com/MathiasTA/Tunes/releases/latest**

2. Scroll down to **Assets** and tap **Tunes.ipa**. The ".ipa" is what an iPhone app file is called.
3. If Safari asks, tap **Download**.

The file goes into the **Files** app, in the **Downloads** folder.

---

## Part 3: Install Tunes

1. Open **LocalDevVPN** and tap **Connect**.
2. Open **SideStore** and go to **My Apps**.
3. Tap the **+** button at the top.
4. Find and tap **Tunes.ipa** (look in **Downloads**).
5. Wait a moment. When **Tunes** appears in the list, it's installed.

Find Tunes on your Home Screen and open it. It'll ask what to call you, and then you're in. 🎶

---

## Part 4: Keep it working (the 7-day refresh)

Apple only lets apps installed with a free Apple Account work for **7 days** at a time. Refreshing resets the 7 days. It takes a few seconds:

1. Open **LocalDevVPN** and tap **Connect**.
2. Open **SideStore** → **My Apps** → tap **Refresh All**.

Do this every few days. The number next to each app shows how many days are left.

**If Tunes stops opening, don't worry.** Your music, playlists and stats are still there. Just do the refresh above and it opens again.

> ⚠️ A free Apple Account can only have **3 sideloaded apps** at a time, and SideStore counts as one. So you can have SideStore, Tunes and one more.

---

## Updating to a new version

New versions of Tunes appear on the same page as before. Tunes' version number is in **Settings → About**.

1. Download the new **Tunes.ipa** the same way as in Part 2.
2. Connect **LocalDevVPN**, open **SideStore** → **My Apps**, tap **+** and pick the new file.

It installs over the old one. **Everything you had stays:** downloads, playlists, likes and stats.

---

## Something went wrong?

| What you see | What to do |
|---|---|
| SideStore says it can't connect to your device | Open **LocalDevVPN**, make sure it says **Connected**, and try again. Make sure you're on **Wi-Fi**. |
| "Untrusted Developer" when opening an app | Settings → General → VPN & Device Management → tap your email → **Trust**. |
| Can't find Developer Mode in settings | Install SideStore first (Part 1, step 3). The setting only appears after that. |
| Tunes won't open after a few days | It needs a refresh. See Part 4. |
| SideStore asks for a "pairing file" | It sometimes needs renewing after an iPhone update. Open **iloader** on a computer again and use its pairing file option, or see "Pairing file" on https://docs.sidestore.io. |
| iloader can't see your iPhone | Unlock your phone, tap **Trust** if asked, and try a different cable or USB port. On Windows, make sure iTunes is installed. |

For problems with SideStore or iloader, the official help is at **https://docs.sidestore.io**.

---

## Good to know

- **It's free.** Tunes, SideStore, LocalDevVPN and iloader all cost nothing.
- **Your Apple Account** is only used to sign the apps so your iPhone accepts them. Tunes never sees it.
- **No account is needed for Tunes.** Everything stays on your phone.
- **Songs come from YouTube** and song info comes from Deezer. If YouTube changes something, downloads can stop working until Tunes gets an update.

---

## For the curious: building your own copy

You don't need this to use Tunes. If you know your way around GitHub: fork this repository, turn on Actions, and run **Build IPA**. Your copy's Releases page then gets its own Tunes.ipa. No Mac is needed.
