<p align="center"><img src="docs/icon.png" width="128" alt="Photos Backup Tracker icon"></p>

<h1 align="center">Photos Backup Tracker</h1>

<p align="center">Make your own copy of every photo and video in iCloud, on an external drive you own.</p>

---

## What it does

If you use iCloud Photos with **Optimize Mac Storage**, most of your photos aren't actually on your Mac. They
live in iCloud, and your Mac only keeps small previews. That's great for saving space, but it means you don't
have a copy of your own.

Photos Backup Tracker fixes that. It copies your photos and videos, originals included, onto an external
drive, sorted into folders by year, month and day. It shows you exactly how much is backed up, and you can
back up a year, a month or a single day with one click.

- **Your Mac doesn't fill up.** Photos are copied to the drive a bit at a time, never all onto your Mac.
- **Nothing is deleted.** The app only copies. It never removes or changes anything in Photos or iCloud.
- **You can stop any time.** Whatever was copied stays on the drive. Next time it continues where it left off.
- **Private.** Everything happens on your Mac, between Apple's Photos app and your drive.

## What you need

- A Mac with **Apple silicon** (M1, M2, M3, M4 or later). Not sure? Click the Apple menu  → **About This
  Mac** and look at "Chip".
- **macOS 14 Sonoma** or newer.
- **iCloud Photos** turned on in the Photos app.
- An **external drive** with enough free space for your library. The app tells you how big your library is.

## Download and install

1. Go to the [**latest release**](../../releases/latest) and download the file ending in **`.dmg`**
   (for example `Photos-Backup-Tracker-0.1.0-arm64.dmg`).
2. Open the downloaded file. A window appears with the app and an **Applications** folder.
3. **Drag Photos Backup Tracker onto the Applications folder.**
4. Close the window, then eject the disk image: in Finder, click the ⏏ next to "Photos Backup Tracker" in the sidebar.

### Opening it for the first time

Photos Backup Tracker is a free, open-source project. It isn't registered with Apple, so the first time you
open it, macOS warns that it **couldn't verify the app**. That's expected. To allow it:

1. Open **Applications** and double-click **Photos Backup Tracker**. When the warning appears, click **Done**.
2. Open **System Settings** → **Privacy & Security**.
3. Scroll down to the **Security** section. Next to *"Photos Backup Tracker" was blocked*, click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open**.

You only need to do this once. After that the app opens normally.

The first time it reads your library and your drive, macOS also asks for permission to access **Photos** and
**removable volumes** (your drive). Click **Allow** both times.

## Using the app

1. **Connect your external drive.**
2. **Choose a backup folder.** The first time, the app asks you to pick a folder on the drive, or you can
   create a new one such as "Photos Backup". It remembers your choice. You can change it later with
   **Backup Folder…** at the top of the window.
3. **See where you stand.** The main screen shows how much of your library is backed up, for example
   *"12,340 of 29,444 photos and videos backed up"*.
4. **Back up.** Click **Browse by Year**, then **Sync** next to a year, a month or a day. A progress bar at
   the bottom shows how far it is. Click **Cancel** to stop.

Next to each year, month and day, an icon shows its status:

| Icon | Meaning |
|---|---|
| ✅ green check | Everything from that period is on the drive |
| 🌗 half-filled circle | Partly backed up |
| ☁️ cloud | Not backed up yet |

### Tips

- **Start with one month** to get a feel for the speed. Photos that are only in iCloud have to be downloaded
  first, which can take a while.
- **Keep your Mac plugged in and awake** during long backups. A sleeping Mac pauses the backup.
- **If your Mac runs low on space**, the app won't start a sync that would fill it up. While copying, Photos
  keeps each photo on your Mac until macOS frees the space by itself. Wait a little, or back up a smaller
  period.

## Where are my photos?

In the folder you chose, inside **Photos Library**, sorted by date:

```
Photos Backup/
└── Photos Library/
    └── 2025/
        └── 07/
            └── 04/
                ├── IMG_0001.HEIC         the photo itself, at full quality
                ├── IMG_0001.mov          the video part of a Live Photo
                └── IMG_0001_edited.jpeg  your edited version, if you edited it in Photos
```

These are normal files, so you can open them with any app. Every frame of a burst is included. Each photo keeps
its date, location and camera details. To bring photos back into Photos, drag the folders into the Photos app.

The **photos-backup-logs** folder next to it keeps a record of every backup.

## Questions

**Does it delete anything from my iPhone, iCloud or Photos?**
No. It only reads from Photos and copies to your drive. It refuses to run in any mode that could delete or
change files.

**Do I have to back up everything at once?**
No. Back up whatever you like, whenever you like. The app shows what's still missing.

**I took new photos. How do I add them?**
Open the app and click **Sync** on the current month. Only the new photos are copied.

**Are albums and people names saved?**
No. Only the photos and videos themselves, with their dates and locations, are copied. Albums, people names and
favourites stay in the Photos app.

**How do I update the app?**
Download the newest `.dmg` from the [releases page](../../releases) and drag the app into Applications again,
choosing **Replace**. macOS may ask for its permissions again.

**How do I remove it?**
Drag Photos Backup Tracker from Applications to the Trash. Your backup on the drive stays where it is.

## For developers

Photos Backup Tracker is open source under the [MIT license](LICENSE). It has a native SwiftUI app and a Python
command-line tool built on [osxphotos](https://github.com/RhetTbull/osxphotos), which can also be used on its
own. See [CONTRIBUTING.md](CONTRIBUTING.md) for building from source, the command-line tool, tests and
releasing, and [architecture.md](architecture.md) for how it fits together.
