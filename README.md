# SUFUN

**SUFUN** is a lightweight Linux system made only for the **Microsoft Surface Go 3**.
Target: **Pentium Gold 6500Y (2 cores), 4 GB RAM, 64 GB eMMC, 10.5" 1920×1280 touchscreen**. Every setting respects those limits.
You mostly use it as a laptop with the Type Cover, and it switches to tablet mode when you detach the cover.

| Layer | Choice | Why |
|---|---|---|
| Base | Arch Linux (archiso) | Small, current, easy to trim |
| Kernel | [linux-surface](https://github.com/linux-surface/linux-surface) | Touch, pen, Type Cover, buttons, battery, cameras |
| Desktop | KDE Plasma 6 (Wayland), Windows 11-style layout | Familiar look; automatic tablet mode |
| Look | Fluent colors/icons, solid Plasma style, Selawik + Noto Sans CJK KR | Windows 11 feel without slow effects |
| Apps | Firefox (+uBlock Origin), LibreOffice (+HWP), Haruna, Snapshot, Steam, Wine | Everyday use, Korean documents |
| Memory | zram 1.5× RAM + earlyoom + MGLRU + ananicy-cpp | 4 GB is enough, and the desktop doesn't freeze |
| Storage | btrfs `compress=zstd:1`, Timeshift snapshots before updates | Fits on 64 GB, easy to undo a bad update |
| Updates | Arch packages with "시스템 업데이트"; SUFUN itself with signed `.sufun` files | Safe, verified updates |

---

## Project layout

```
VERSION                     The SUFUN version (1.0). Bump it for a new release.
build.sh                    Builds the ISO (run as root on Arch)
build-local-repo.sh         Builds our own packages (makepkg only, no AUR downloads)
sufun-base/                 The "sufun-base" package: ALL SUFUN settings and tools
  rootfs/                     files installed to / (settings, scripts, boot screen...)
  PKGBUILD, sufun-base.install, art/ (SVG pictures rendered at build time)
sufun-keyring/              The "sufun-keyring" package: the public signing key
keys/                       sufun.asc (public key, made by scripts/sufun-key.sh), sufun-revoked
packages/desktop.txt        Official packages (dependencies of sufun-base)
packages/install.txt        Extra base packages for the installed system
packages/aur.txt            Our own packages, in build order (AUR copies + our recipes)
packages/pkgbuilds/         Pinned copies of every non-official package we use
profile/airootfs/           Live-USB-only files (auto-login, installer, CI self-test)
release-notes/<ver>.txt     Korean release notes shown in the update dialog
scripts/                    sufun-key.sh, make-sufun-update.sh, check-aur-updates.sh, ci/
.github/workflows/          build-iso.yml (test builds), release.yml (releases), build-test.yml (shared)
```

---

## Windows 11-style desktop

Default for every new user, on the live USB and on the installed system (all in `sufun-base`). The wallpaper stays Plasma's default. Blur, transparency and rounded-corner window effects stay **off** (speed). No Microsoft logo, font or icon is shipped: the start button is the SUFUN logo, the font is Selawik, the icons are Fluent.

**Taskbar** (left to right): `[space]` start button · **검색** box · Task View · Files, Firefox, Konsole, Settings `[space]` tray (`^`, 한/영, network, volume, battery) · clock. Running apps get the small line under their icon (Plasma's normal task indicator).

| Part | How it is done | Why this way |
|---|---|---|
| Start button | Icon theme **"SUFUN"** (in `sufun-base`) = Fluent + the SUFUN logo for every `start-here*` name | Fluent's start icons are the Windows logo. Our theme sits *on top of* Fluent, so Fluent updates can't bring the Windows logo back. The Windows logo is also removed from `sufun-fluent-icons` (with Edge/Office/Teams/Skype/OneDrive logos, 59 files), and Fluent's Office file-type icons that copy the Word/Excel/PowerPoint/Outlook logos are removed too (.docx/.xlsx/.pptx files show Fluent's plain document/spreadsheet/presentation icons) and from the Plasma style (`icons/start.svgz`). |
| 검색 box | Small SUFUN widget `org.sufun.search` → opens **KRunner** (apps, recent files, folders, settings, calculator) in the middle of the screen | Plasma has no search *field* for the panel. KRunner is Plasma's own search. File-content search is off (Baloo indexing uses too much CPU/RAM). |
| Task View | Small SUFUN widget `org.sufun.taskview` → KWin **Overview** | Plasma 6.8 has no Overview button widget. |
| Clock | Small SUFUN widget `org.sufun.clock`: two lines, right-aligned, same size. Korean `오전 2:33` / English `2:33 AM`, below it `2026-11-12`. Click = Plasma's calendar | Plasma's Digital Clock always puts 오전/오후 *after* the time, draws the date smaller and centers both lines. |
| Start menu | **Kickoff** (Plasma's own): pinned apps as a grid, user name + picture, power buttons. Pinned apps: `/etc/xdg/kicker-extra-favoritesrc`. Recent files: *Places → History* | See "Start menu: Kickoff, not Menu 11" below. |
| Desktop icons | 휴지통, Firefox, Steam, LibreOffice Writer, 메모장, in columns from the top-left, 48 px, double-click to open | Made by `/usr/lib/sufun/first-login` in the user's desktop folder (`~/바탕화면` in Korean). The desktop sorts by date (oldest first), so this order stays and new files appear at the end, like Windows. |
| Tray | Always visible: 한/영 (Fcitx5 shows text, not an icon), network, volume, battery. Behind `^`: Bluetooth, notifications, clipboard, brightness | Set by the layout script (Plasma 6.8 keeps them in the tray widget's own settings). Win+N is added by `first-login`: the notifications widget inside the tray only exists after Plasma starts, so at the first login the shell is stopped for ~2 s (it saves the tray when it quits), the shortcut is written, and it starts again. |
| Alt+Tab | KWin **Thumbnail Grid**: live window previews | The only switcher with previews that comes with KWin itself (the others need `kdeplasma-addons`, +19 MB). |
| Files (Dolphin) | Places pane on the left (Home, Desktop, Documents, Downloads, Pictures, ..., drives under *Devices*), address bar you can type into | Folder names follow the language (`xdg-user-dirs`): 바탕화면, 문서, 다운로드, 사진, ... |

**Windows shortcuts** (`/etc/xdg/kglobalshortcutsrc`):

| Keys | Opens |
|---|---|
| Win | start menu |
| Win+R | run box (KRunner) — taken from Spectacle's "record region" (now Win+Shift+R) |
| Win+I | Settings |
| Win+E | Files |
| Win+Tab | Task View (Overview; Win+W still works). Removed from "switch windows" (Alt+Tab) and "switch activities" |
| Win+V | clipboard history (Plasma default) |
| Win+Shift+S | screenshot of an area (Spectacle, right away) |
| Win+A | tray = quick settings (Wi-Fi, volume, battery, brightness, Bluetooth) |
| Win+N | notifications |
| Win+D / Win+L / Win+arrows | desktop / lock / snap windows (as before) |
| Ctrl+Shift+Esc | Task Manager (System Monitor; Win+Esc also works) |

**Task Manager: plasma-systemmonitor (chosen) vs. htop.** plasma-systemmonitor costs **+3.0 MB** on disk (everything it needs is already installed with Plasma) and uses RAM only while it is open (measured: about **190 MB** while open, plasma-systemmonitor 186 MB + ksystemstats 7 MB); htop (already installed, 0.4 MB) inside Konsole uses much less (about **43 MB** with Konsole) but is a terminal program that is hard to use with touch. plasma-systemmonitor works like the Windows Task Manager (click a program, *End Process*). htop stays installed. The CI live test measures both every build: see the `INFO ram task-manager` lines in `1-live-serial.log`.

**Start menu: Kickoff, not Menu 11.** The closest community menu, "Menu 11 Next" (GPL licence tag but no licence file; one-person fork), is ~6,000 lines of QML that uses Plasma's *private* start-menu API, was last released before Plasma 6.8, sends search text to DuckDuckGo and copies with X11-only tools. Arch updates Plasma all the time, so a broken start menu after an update would be the worst possible failure. Kickoff is updated together with Plasma. Differences you will see: user name/picture is at the **top** (Windows: bottom), and recent files are under *Places → History* instead of on the first page.

**Cost of everything added:**

| | Disk | RAM |
|---|---|---|
| plasma-systemmonitor | +3.0 MB | about 190 MB, only while open (0 when closed) |
| 3 SUFUN widgets (search, Task View, clock) | ~15 KB | a few MB inside the Plasma shell (small QML; the calendar loads only when you open it) |
| SUFUN icon theme (PNG start logo, 9 sizes) | ~0.2 MB | – |
| Removed Microsoft/Windows logos | −59 icon files, plus the Office-logo file-type icons | – |
| Desktop icons (5 shortcuts) | a few KB | the desktop was already a Folder View; a few MB for 5 icons |
| Alt+Tab thumbnails, Overview, KRunner | 0 (part of KWin/Plasma) | only while open |
| Settings files | a few KB | – |
| **Total** | **≈ +3 MB** | **a few MB always; more only while an app/popup is open** |

The CI live test also prints the Plasma shell's and KWin's memory after login (`INFO ram plasmashell ...`), so changes can be compared build by build.

---

## Changes in this update and why

### Build fixes (items 1, 2, 4, 5, 26)
| What | Why |
|---|---|
| `sufun-fluent-theme` PKGBUILD: the upstream `install.sh` now runs in `build()`, `package()` only copies | `package()` runs under *fakeroot*, where `$UID` is 0, so `install.sh` tried to write to `/usr/share` and the build failed. Also changed from a git checkout (`SKIP` checksum) to a pinned tarball with a real sha256. |
| Workflow: first step deletes unused tools on the runner (.NET, Android SDK, GHC, tool cache, Boost) and prints free space; container gets `-v /:/host` | GitHub only guarantees about 14 GB of disk. |
| Bottles is commented out in `packages/aur.txt` (with its 4 helper packages) | Bottles has the most dependencies and is the most likely to fail. **After the first successful build, remove the `#` from those 5 lines.** |
| **When you push to `main`, the build starts by itself.** Don't also start it with `gh workflow run`, or it builds twice. | |
| **No more AUR downloads during the build.** Every AUR package we use is copied into `packages/pkgbuilds/`, pinned to an exact version with real checksums, and built with plain `makepkg`. `yay` is gone. | Like KDE Linux: what you build is exactly what you reviewed. |

**Security review of the copied AUR recipes (item 26).** In every PKGBUILD I checked for: downloads during the build (curl, wget, pip, npm), `curl | sh`, install scripts doing more than refreshing caches, files written outside the package, sources that aren't the official upstream project, and obfuscated code. **Nothing risky was found.**

| Package | Pinned | Notes |
|---|---|---|
| ttf-selawik | 1-5 (commit) | Only copies fonts. md5 replaced by sha256. |
| cachyos-ananicy-rules | 1.1.49 | Non-`-git` package from the AUR (maintained by Arch developers); only copies rule files. |
| libreoffice-extension-h2orestart | 0.7.13 | Unzips the official `.oxt` system-wide. Upstream already has 0.8.0, see "Checking the AUR" below. |
| bottles | 67.6 | Offline meson build. At runtime Bottles itself downloads Wine runners when you ask it to (normal for Bottles). |
| fvs2 | 0.11.0 | Go build. `go mod download` uses the network, but it is locked by `go.sum` (checked hashes). |
| patool, vkbasalt-cli, python-setuptools-reproducible | 4.1.0 / 3.1.1 / 0.1 | Plain Python builds. vkbasalt-cli was a git checkout with `SKIP`, now a tarball with sha256. |

### Everything SUFUN in one package: `sufun-base` (item 23)
All settings that used to be copied by the installer (`SHARED_FILES`) are now files of a real pacman package, **sufun-base** (version = `VERSION`). Its dependencies are `packages/desktop.txt` + our own packages, so installing `sufun-base` installs the whole desktop. The installer just runs `pacstrap ... sufun-base`.

Files that another package also owns can't simply be put in a package. They are handled like this:

| Setting | Owned by | How SUFUN sets it |
|---|---|---|
| `/etc/environment` (Fcitx5 for X11 apps) | pam | **Drop-in** `/etc/environment.d/50-sufun.conf` instead |
| `/etc/bluetooth/main.conf` (radio off until switched on) | bluez | Install script changes only `AutoEnable=false`; bluez keeps our value on updates (it writes `.pacnew`) |
| `/etc/plymouth/plymouthd.conf` (boot screen theme) | plymouth | Install script sets `Theme=sufun`, `ShowDelay=0` the same way |
| `/usr/lib/os-release` (version shown in Settings) | filesystem | Pacman hook `95-sufun-os-release.hook` copies ours back after every `filesystem` update (same as CachyOS/EndeavourOS) |
| `/etc/lsb-release` | lsb-release | Same hook |
| `/etc/ufw/ufw.conf`, `/etc/default/ufw` | ufw | Installer changes single values |
| sysctl, udev, modprobe, journald, coredump, logind, zram, tmpfiles, service drop-ins | — | Packaged in `/usr/lib/...` (the place for packages); your own changes in `/etc/...` still win |
| SDDM Wayland setting | — | `/usr/lib/sddm/sddm.conf.d/50-sufun.conf`, so System Settings can still write `/etc/sddm.conf.d/kde_settings.conf` |
| `/etc/xdg/*` KDE defaults, Firefox policy, fonts, Fcitx5 | not owned | Packaged directly; listed in `backup=()` so your edits survive updates |
| FeatherPad and Steam launchers | featherpad, steam | Same-named files in `/usr/local/share/applications`, which is searched first |

I checked every file in `sufun-base/rootfs` against the real Arch file lists: no conflicts with packages we install.

### Korean input (item 3)
`/etc/xdg/fcitx5/profile`: one group "Default" with **keyboard-us** and **hangul**, layout us.
`/etc/xdg/fcitx5/config`: switch with **Hangul**, **Shift+Space** or **Right Alt**.
⚠️ **Check on the first boot**: in a text field, press Right Alt and type `dkssud` → it should show `안녕`.

### RAM for 4 GB (item 7)
| Change | File | Estimated saving |
|---|---|---|
| uBlock Origin (force-installed) | `etc/firefox/policies/policies.json` | Ad-heavy pages use 20–40% less RAM: often 50–150 MB per busy tab (uBlock itself uses ~30 MB) |
| `browser.sessionhistory.max_total_viewers = 0` | same | Firefox keeps no old pages in RAM for "Back": up to ~50–150 MB after a long session. "Back" reloads instead. |
| Site isolation (Fission) | — | **Left on** on purpose: it protects you from malicious websites |
| 6 KDE background modules off | `etc/xdg/kded5rc` | ~5–10 MB and fewer wake-ups (see list below) |
| MGLRU thrashing protection | `usr/lib/tmpfiles.d/sufun-mglru.conf` | No RAM saving: it stops the multi-second freezes when RAM is full (`min_ttl_ms=1000`) |
| Steam quits when you close it | `usr/lib/sufun/steam-launch` | ~300–500 MB that a hidden Steam would keep |

**MGLRU check:** the linux-surface kernel is built from Arch's config plus Surface options, and Arch's config has `CONFIG_LRU_GEN=y` and `CONFIG_LRU_GEN_ENABLED=y`. The Surface options don't change them. So `/sys/kernel/mm/lru_gen/min_ttl_ms` exists.

**KDE background modules switched off** (`/etc/xdg/kded5rc`; KDE 6 still uses this file name):

| Module | What it does | Why off |
|---|---|---|
| donationmessage | yearly "donate to KDE" pop-up | not needed |
| smbwatcher | watches Windows network shares | no network shares |
| wpad_detector | proxy auto-detection | home Wi-Fi has no proxy |
| remotedirnotify | watches `remote:/` network folders | not used |
| appmenu | global menu bar | our taskbar has no global menu |
| baloosearchmodule | updates Baloo search folders | Baloo indexing is already off |

**Kept on**: Wi-Fi (networkmanagement), Bluetooth (bluedevil), sound and media keys (audioshortcutsservice, mprisservice), USB drives (device_automounter, soliduiserver, solidautoeject, devicenotifications), tray, low-disk warning. Battery, rotation and the Type Cover are not kded modules any more in Plasma 6.8 (PowerDevil and KWin do them). Thunderbolt (`kded_bolt`) and printing modules don't exist here, because those packages aren't installed.

### Cameras (item 8)
The old README was wrong: the linux-surface wiki lists the Surface Go 3 **front (OV5693) and rear (OV8865) cameras as working** through IPU3 + libcamera. Only the **IR camera (OV7251, for face login) does not work**.

- Packages: `libcamera`, `libcamera-ipa`, `pipewire-libcamera` (apps get the cameras through PipeWire), `libcamera-tools` (`cam`, `qcam`). 14 MB.
- IPU3 IMGU firmware: in `linux-firmware-intel`, which we already install. The wiki says it must be there "at kernel boot". The camera driver loads from the main system disk, not the initramfs, so having it on the disk is enough. No initramfs change is needed.
- Firefox: `media.webrtc.camera.allow-pipewire = true`, so video calls can use the cameras.
- Camera app: **Snapshot** (GNOME Camera, works through PipeWire/libcamera). **+96 MB** with dependencies (GTK4, GStreamer).
  Smaller alternative: **`qcam`** is already included (0 MB extra), but it is a test viewer, not a real camera app. KDE's Kamoso is 89 MB and doesn't use libcamera, so it can't see these cameras.

**Testing the cameras after the first boot:**
```bash
cam --list          # should list 2 cameras (ov5693, ov8865)
qcam                # quick live picture
```
Then open **Snapshot**, and try a video call test page in Firefox. If `cam --list` shows nothing, run `sudo dmesg | grep -i -E 'ipu3|ov5693|ov8865|int3472'` and send me the output.

### Apps (items 6, 9, 13, 29)
| App | Size added (with dependencies) | Notes |
|---|---|---|
| htop | 0.4 MB | Task manager in the terminal |
| KCalc | 3.2 MB | Calculator |
| Haruna | 19.8 MB | Video/music player (mpv). **Hardware decoding on**: `[Playback] HWDecoding=auto-safe` in `/etc/xdg/haruna/haruna.conf` and `/etc/skel/.config/haruna/haruna.conf`. Haruna does **not** read `/etc/mpv/mpv.conf` (it uses libmpv with its own settings), so mpv.conf would do nothing. |
| 7zip + unrar | 6.9 MB | Ark backends: `7z` creates 7z and encrypted archives; `unrar` extracts RAR. Password-protected ZIP already works through Ark's libzip backend. |
| Notepad (FeatherPad) | 0 | Shown as **메모장 / Notepad**. Default for .txt, .log, .md. `.ini` and `.conf` have no own file type, so they count as plain text and open in Notepad too. |

Haruna is the default for mp4, mkv, webm, avi, mov, mp3, m4a, flac, ogg/opus and wav (`etc/xdg/mimeapps.list`).

### USB drives, phones, formatting (items 10, 11)
| Package | Size added | Why |
|---|---|---|
| ntfs-3g, exfatprogs | 1.6 MB | NTFS drives from Windows; check/format exFAT |
| kio-extras, libmtp, udisks2 | 0 (already pulled in by Plasma) | Android file transfer (MTP needs `libmtp`, which kio-extras brings), thumbnails, USB auto-mount |
| partitionmanager + dosfstools | 13.8 MB | Format USB drives as FAT32/exFAT/NTFS. `dosfstools` is now in `desktop.txt`, so it is on the live USB too. |

**NTFS:** udisks2 uses the kernel's fast **ntfs3** driver first, and ntfs-3g as a fallback (its default: `ntfs_drivers=ntfs3,ntfs`). No extra configuration is needed. If a Windows drive refuses to mount, Windows probably left it "dirty": plug it into Windows and use *Safely remove*, or turn off Windows *Fast startup*.
**Password prompts:** Partition Manager asks for the admin password through polkit. `polkit-kde-agent` is a dependency of Plasma, and it is listed explicitly too.

> ⚠️ **Partition Manager also shows the internal drive** (`/dev/mmcblk0`, about 58 GB) — that is SUFUN itself. **Always check the disk name and size before formatting.** USB drives appear as `/dev/sdX` (`/dev/sda`, `/dev/sdb`...).

### Screen scaling (item 12)
- Plasma's own choice for this panel would be about **160%** (KWin aims for ~125 DPI on laptop panels, capped by height: 1280 ÷ 800 = 1.6), or 170% if no lid switch is detected. So it does **not** pick 150% by itself.
- SUFUN sets **150%** once, at each user's first login (`/usr/lib/sufun/first-login`, using `kscreen-doctor`). You can change it any time in *System Settings → Display*.
- **X11 apps (including Wine):** Plasma's default "apply scaling themselves" is kept. X11 apps get **144 DPI** (= 1.5 × 96), so they draw themselves at the right size and stay sharp (not blurry, not tiny). Wine doesn't read that value, so `sufun-wine` now sets Wine's **LogPixels = 144** when it prepares `~/.wine`. If you change the screen scale later, change it in Wine too: `winecfg` → Graphics → Screen resolution.
  Why 150% and not 160%: 150% is an exact multiple of 96 DPI, so X11/Wine programs scale cleanly. It also gives more room on a small screen.

### Pen and touch (item 14)
- **libwacom-surface: not added.** It is not in the linux-surface repo (AUR only). Its extra data covers only Surface Pro/Book/Laptop models. Arch's normal `libwacom` already knows the Go 3 touchscreen (`ELAN 04F3:2A1C`, in its "Surface Go 2" data, same panel). So it would change nothing on the Go 3.
- **iptsd: not needed.** iptsd is for Intel IPTS touchscreens (Surface Pro 4 and newer, Book, Laptop). The linux-surface wiki explicitly excludes "the Surface Go lineup": the Go 3 touchscreen is a standard I2C HID screen handled by the normal kernel driver.

### Backups before updates: Timeshift (item 15)
- **Timeshift** in btrfs mode. Our layout matches what it needs: `@` and `@home` at the top level, root mounted with `subvol=@`. Timeshift snapshots **only `@`** (`include_btrfs_home_for_backup=false`), so `@home` (your files), `@log` and `@pkg` are never in system snapshots. The installer writes `/etc/timeshift/timeshift.json`.
- **fstab fix:** `genfstab` writes `subvolid=...`. After a restore, `@` gets a new ID, and the system would no longer boot. The installer removes `subvolid=` so subvolumes are mounted **by name** only.
- **Pacman hook** `05-sufun-snapshot.hook` (our own): before every upgrade or removal it runs `timeshift --create`, then deletes older hook-made snapshots so only the **newest 3** remain. Snapshots you make yourself are never deleted. If a snapshot fails, the update still continues and a warning is printed.
- **"시스템 업데이트 (System Update)"** in the app menu: opens Konsole, runs `sudo pacman -Syu` (the hook makes the backup first), and waits for Enter. ⚠️ It does **not** update our own packages (Selawik font, ananicy rules, H2Orestart, Bottles, sufun-base...). Those come with the next `.sufun` update file.
- **Disk use of 3 snapshots:** a new snapshot takes almost no space. It grows only by the files that later change. Each snapshot keeps the *old* versions of the files an update replaced. A normal Arch update replaces roughly 0.5–1.5 GB of files (more when Firefox, LibreOffice, the kernel or Mesa update together), and zstd shrinks that by ~30%. **Expect about 1–3 GB for 3 snapshots, rarely up to ~4 GB.** Check with `sudo timeshift --list` and `sudo btrfs filesystem usage /`.

**Restoring a snapshot (simple steps)**

*From the running system* (it starts, but something is broken after an update):
1. Open the app menu → **Timeshift** (it asks for your password).
2. Pick the snapshot from just before the update (description: `sufun-autosnap: 업데이트 전 자동 백업`).
3. Click **Restore** → **Next** → confirm. The computer restarts into the old system.
   Your personal files (`@home`) are not touched.

*From the live USB* (the system doesn't start any more):
1. If you set a UEFI password (see "UEFI 암호" below): turn the Surface off, hold **Volume Up** and press **Power**, enter the UEFI password, and under **Boot configuration** turn **USB Storage** on again.
2. Plug in the SUFUN USB, hold **Volume Down** and press **Power**.
3. On the live desktop, open Konsole and run `sudo timeshift-launcher` (Timeshift is on the live USB too).
4. Timeshift asks which disk: choose the internal drive (`mmcblk0p2`, btrfs). Pick the snapshot → **Restore**.
5. Restart without the USB. Then turn USB boot off again in UEFI.

### Office documents and HWP (item 16)
- **LibreOffice Still** (26.2) + Korean language pack (`libreoffice-still-ko`). **Why "still" and not "fresh":** "still" is the mature branch that still gets security fixes but no big feature changes, so there are fewer surprises for daily documents. "Fresh" (26.8) has the newest features but more new bugs. Both are the same size; switching later is just a package swap.
- The KDE/Qt look is used automatically on Plasma (the `kf6` plugin is included in the package, and `kio` + `qt6-multimedia` are installed).
- **H2Orestart** extension (from our pinned AUR copy, installed system-wide): opens **.hwp and .hwpx**. These files open in LibreOffice Writer by double-click.
- **Fonts:** `etc/fonts/local.conf` maps 함초롬바탕/HCR Batang, 한컴바탕, HY신명조, 바탕, 궁서... → **Noto Serif CJK KR**, and 함초롬돋움/HCR Dotum, 한컴돋움, HY견고딕, 돋움, 굴림, 맑은 고딕... → **Noto Sans CJK KR**.
- **Size added: ≈ 805 MB** (LibreOffice 422 MB + Korean pack 34 MB + Java runtime 175 MB for H2Orestart + libraries).
- **RAM while open (estimate):** Writer with a normal document ≈ 200–250 MB. Opening an HWP file also starts Java: ≈ 350–450 MB in total. Close LibreOffice when you don't need it.

### Firewall (item 17)
`ufw` + `plasma-firewall` (*System Settings → Firewall*). The installer turns it on: **block incoming, allow outgoing**, and enables `ufw.service`. Replies to your own connections are allowed (web, DHCP for getting a Wi-Fi address). Bluetooth and Android file transfer (USB/MTP) don't use the network, so the firewall doesn't touch them. (Size: 1.9 MB.)

### CPU power profile (item 18)
`/etc/xdg/powerdevilrc`: **Performance** on the charger, **Balanced** on battery, **Power Saver** on low battery. **thermald** stays enabled, so the fanless Surface still slows down safely when hot.
**Not done on purpose:**
- **No higher CPU power limits (PL1/PL2).** The Surface Go 3 has no fan; more watts just means more heat, quick throttling, a hot back panel and a shorter battery life. The firmware limits are designed for this case.
- **No `mitigations=off`.** It turns off protections against CPU attacks such as Spectre. A web page's JavaScript could then read other memory, for example passwords in another tab. On a dual-core Pentium the speed gain is small.

### Type Cover lid (item 19)
- Closing the Type Cover = **sleep**, also on the charger. This is set in both places: Plasma (`powerdevilrc`, used while you're logged in) and logind (`/usr/lib/systemd/logind.conf.d/50-sufun-lid.conf`, used at the login screen). With an external monitor, closing does nothing.
- **Lock screen:** after waking from sleep, and after **5 minutes** without use (`/etc/xdg/kscreenlockerrc`).
- **surface_gpe:** the kernel's `surface_gpe` driver (which makes *opening* the lid wake the device on other Surfaces) **does not list the Surface Go 3**. A wiki user reports the same. The Go 3 does have a normal ACPI lid switch (`LID0`), so closing works. Whether *opening* wakes it is not certain. No risky workarounds were added.
- **Folding the Type Cover back:** the kernel's `intel-hid` driver reports "tablet mode" on the Surface Go (it has a special entry for it). Then libinput **disables the keyboard**. The **touchpad may stay active**, because its USB ID (045e:09b5) is not in systemd's list of internal touchpads, so it counts as "external". If that bothers you, a 2-line hwdb rule can fix it after we confirm it on the device.

**First-boot test checklist (lid):**
1. Close the Type Cover → after ~2 s the screen goes off and it sleeps? (the power LED/keys stop)
2. Open it → does it wake and show the lock screen? **If not, press the Power button** — that always wakes it.
3. Fold the cover behind the screen → keys stop typing? Touchpad stops?
4. Repeat 1–2 about 10 times (there is a known linux-surface report of rare "sleep of death" on the Go 3).

If something fails, send me: what you did, what happened, and the output of
`journalctl -b -1 -n 200 --no-pager | grep -i -E 'lid|suspend|s2idle|resume'` and `cat /proc/acpi/wakeup`.

### Password, lock screen and tablet keyboard (item 20)
- The password stays required at boot (SDDM) and on the lock screen.
- *System Settings → Users* (change password, account picture) works: `accountsservice` is installed.
- *System Settings → Login Screen (SDDM)* → auto-login works: it writes `/etc/sddm.conf.d/kde_settings.conf`, and SUFUN's own SDDM settings are in `/usr/lib/sddm/...`, so they don't clash.
- **The keyboard problem, fixed:** KWin can run only **one** input method, and Fcitx5 has no on-screen keyboard. With Fcitx5 always on, the lock screen in tablet mode had no keyboard to type the password.
  **Fix:** a small user service `sufun-input-switch` (`/usr/lib/sufun/input-switch`) listens to KWin's tablet-mode signal (D-Bus `org.kde.KWin.TabletModeManager`):
  - Type Cover attached → **Fcitx5** (Korean/English)
  - cover detached or folded back → **Plasma on-screen keyboard** (also on the lock screen)
  
  It writes `kwinrc [Wayland] InputMethod` with `kwriteconfig6 --notify`; KWin restarts the input method within about a second.
  **Trade-offs:** the on-screen keyboard has **no Korean layout** (Plasma Keyboard doesn't offer one yet), so in tablet mode you type English/numbers only. Korean needs the Type Cover. A text field focused at the moment of switching may need one more tap.
  **Test:** lock (Win+L), detach the cover, tap the password field → the on-screen keyboard appears? Attach the cover → Right Alt switches to Korean again?
- **Short PIN like Windows Hello:** Linux has one account password for everything (login, lock screen, sudo). Options:
  1. **A shorter but not trivial password** (e.g. 6–8 characters with a number). Simple, no extra software. **Recommended**, together with the UEFI password and auto-lock.
  2. A separate PIN through a PAM module (e.g. `pam_pwdfile`) — only in the AUR, not in the official repos, and a mistake in the PAM setup can lock you out. **Not installed.**
- **Windows Hello face/fingerprint login is not possible** on this device: the IR camera (OV7251) is not supported on Linux, and the Surface Go 3 has no fingerprint reader.

### New name: SUFUN, and the boot screen (item 21)
- Renamed everywhere you can see it: ISO name `sufun-<version>-x86_64.iso`, label `SUFUN_YYYYMM`, live boot menus (GRUB, systemd-boot, syslinux: "SUFUN live USB / installer"), installed boot entry "SUFUN", installer "Install SUFUN / SUFUN 설치", default computer name `sufun`, live user `sufun`. Internal names too: `org.sufun.desktop` (global theme), `sufun-install`, `sufun-wine`, `sufun-fluent-theme`, `sufun-fluent-icons`, local repo `sufun-local`. SUFUN is still made only for the Surface Go 3.
- **Boot screen (Plymouth)**: black background, **"SUFUN"** in the middle (white, Selawik semibold), small spinner below. The text and the spinner are **pre-rendered to PNG when sufun-base is built** (`rsvg-convert` from `sufun-base/art/*.svg`), so no fonts are needed at boot.
  - Initramfs: `/etc/mkinitcpio.conf.d/10-sufun.conf` = Arch's systemd-based list with `plymouth` right after `systemd` (the Arch wiki requires that order). Kernel options get `splash`.
  - Hand-over to the login screen: `sddm.service` drop-in quits Plymouth with `--retain-splash` (the last picture stays on screen until SDDM draws), the same idea GDM uses. That avoids the black text console in between. A short flicker is still possible with SDDM.
  - **Installed system only.** On the live USB, Plymouth with archiso's (non-systemd) boot hooks has no reliable, confirmed setup, so the live USB keeps text boot. I'd rather not risk the installer USB not starting.
- The **Surface logo shown first comes from the device firmware (UEFI)** and can't be changed.

### Version in Settings (item 22)
- `kinfocenter` added → *System Settings → About this System*. (+48 MB, mostly diagnostic tools it needs.)
- `VERSION` (1.0) → sufun-base writes `/usr/share/sufun/os-release`: `NAME="SUFUN"`, `PRETTY_NAME="SUFUN 1.0"`, `VERSION`, `VERSION_ID`, `BUILD_ID` (build date), `ID=sufun`, `ID_LIKE=arch`, `HOME_URL` (your GitHub repo, taken from the workflow).
- **ID=sufun is safe:** pacman, the linux-surface repo, Wine, Steam, Flatpak and Firefox don't look at os-release to decide anything. KDE only shows the name. Tools that don't know "sufun" fall back to `ID_LIKE=arch` (fastfetch then shows the Arch logo). Only rare scripts that check exactly `ID=arch` could complain.
- **Keeping it after updates:** `/usr/lib/os-release` belongs to Arch's `filesystem` package, so an update would bring back "Arch Linux". The pacman hook `95-sufun-os-release.hook` copies ours back right after every `filesystem` update. `/etc/os-release` is a link to it. Why a hook and not `NoUpgrade`/`NoExtract` in pacman.conf: `NoUpgrade` only writes a `.pacnew` file, and both need changes in `/etc/pacman.conf` that a user might undo. The hook is what CachyOS and EndeavourOS use.
- `/etc/xdg/kcm-about-distrorc`: name SUFUN, SUFUN logo, website, variant "Surface Go 3".

### Steam (item 28) — see the Korean section "Steam 안내" below
- `[multilib]` is enabled for the ISO build and on the installed system.
- `steam` with the drivers chosen explicitly: `lib32-mesa`, `lib32-vulkan-intel`, `vulkan-intel`, font `ttf-dejavu`, so `--noconfirm` can never pick an NVIDIA/AMD driver. **+541 MB** with dependencies.
- **No autostart, guaranteed:** Plasma starts `~/.config/autostart/*.desktop` files as systemd user units named `app-<name>@autostart.service`. sufun-base **masks** `app-steam@autostart.service` (a link to `/dev/null` in `/etc/systemd/user`), so even if *"Run Steam when my computer starts"* is turned on, Steam stays off. Plasma's session restore also excludes Steam (`/etc/xdg/ksmserverrc`).
- **Closing = quitting:** `STEAM_FRAME_FORCE_CLOSE=1` is set for the session (`/etc/environment.d/50-sufun.conf`), but on its own it only makes the close button hide Steam in the tray; **it doesn't quit Steam.** So the Steam launcher now goes through `/usr/lib/sufun/steam-launch`:
  1. It notices when no Steam window is open any more. Minimized still counts as open.
  2. If **no game is running**, it runs `steam -shutdown` (a clean quit).
  3. After Steam's main process has exited, it closes leftover `steamwebhelper` processes of your user.
  4. Starting a game and then closing Steam's window does **not** quit Steam while the game runs.
- earlyoom: `steamwebhelper` (Steam's built-in browser) is now killed **before** the game when memory runs out. The old `.exe` rule was removed: Proton games run as `<game>.exe`, so it would have killed the game first.

### Size summary
Measured from the real Arch package database (all dependencies, before btrfs compression), for the installed system:

| | Packages | Installed size |
|---|---|---|
| Before this update (old lists) | 699 | ≈ 4.8 GB |
| After this update | 914 | **≈ 6.3 GB** (+1.5 GB: mostly LibreOffice + Java 805 MB, Steam 541 MB, Snapshot 96 MB, kinfocenter 48 MB) |
| + our own packages (fonts, icons, H2Orestart, sufun-base) | — | a few tens of MB |

With btrfs + zstd the real space on the eMMC is about 30–40% lower. Plus up to ~1–3 GB for 3 Timeshift snapshots.

### Earlier decisions (still in place)
- **Windows programs:** Wine (WoW64 build: 32- and 64-bit programs without `lib32-*` packages) + winetricks. Double-click `.exe`/`.msi`/`.lnk` opens `sufun-wine`. The first time, it maps Gulim, Dotum, Batang, Malgun Gothic (and Korean names) to Noto CJK KR, so Korean text shows. Right-click → *Open in Korean mode* is for old non-Unicode Korean programs. wine-mono/wine-gecko are downloaded only when a program needs them.
- **Bottles** (when switched back on) is the native build: about 100 MB instead of 1.3–1.6 GB for the Flatpak. Choose the system Wine runner (`sys-wine-…`) for new bottles. The Korean font mapping is only in `~/.wine`; add the same font replacements in a bottle's *Registry* settings if needed.
- **Memory:** zram = 1.5 × RAM with zstd (≈ 3:1, so 6 GB of swapped data uses ≈ 2 GB of RAM), `swappiness=180`, `page-cluster=0`; earlyoom instead of systemd-oomd (it kills one process, Firefox tabs and Steam's built-in browser first, never the desktop; `.exe` programs are no longer preferred, because Proton games run as `<game>.exe`); no swap file or partition on the eMMC (so no hibernation, normal sleep works).
- **Storage:** btrfs `noatime,compress=zstd:1` (≈ 30–40% smaller, usually no slowdown on the slow eMMC; `df` numbers are less exact, use `btrfs filesystem usage /`), logs capped at 100 MB, no crash dumps, weekly package-cache cleanup keeping 1 version (`-rk1`; change to `-rk2` to keep one older version).
- **Smaller extras chosen before:** `linux-firmware-intel` instead of all firmware (−277 MB), Firefox opens PDFs instead of Okular (−122 MB), DejaVu + Liberation instead of all Noto fonts (−93 MB), FeatherPad instead of KWrite (−47 MB), no man pages. Possible further saving: `adobe-source-han-sans-kr-fonts` (31 MB, Korean only) instead of `noto-fonts-cjk` (299 MB).
- **Graphics/power:** HuC firmware with `i915.enable_guc=2` (3 would turn on GuC submission, which this GPU generation doesn't support), Firefox VA-API on and AV1 off (no AV1 hardware decoding on the UHD 615), Bluetooth starts on demand with the radio off, no printing (CUPS) installed, ananicy-cpp priorities by program type (it can't know which window is in front).
- **Start menu:** KDE's Kickoff (see "Windows 11-style desktop" above for why not Menu 11). Kvantum and Aurorae are not used (slower).

---

## Releasing a new SUFUN version (item 23, simple steps)

1. Change the settings/files you want (for example in `sufun-base/rootfs/`).
2. Open `VERSION` and raise the number, e.g. `1.0` → `1.1`.
3. Write the Korean release notes in `release-notes/1.1.txt`. If an update can only be installed on top of a certain version, put that version in `release-notes/1.1.min-from` (e.g. `1.0`).
4. Commit and push to `main` → a **test build** starts by itself (unsigned test ISO + boot test). Wait until it is green.
5. Make the release:
   ```bash
   git tag v1.1
   git push origin v1.1
   ```
6. GitHub builds and tests again, then **waits for your approval** (environment "release"). Open *Actions → Release → Review deployments → Approve*.
7. When it finishes, *Releases → SUFUN 1.1* has: `sufun-update-1.1.sufun`, the ISO (or ISO parts + Korean joining instructions), `ISO-SHA256.txt`, `SHA256SUMS` and `SHA256SUMS.asc` (signature).

**Installing it on the Surface:**
- Download `sufun-update-1.1.sufun` and **double-click** it. A Korean dialog shows *current version → new version* and the release notes, with **[업데이트] [취소]**.
- Click 업데이트 → enter your password → it checks the file, makes a Timeshift backup, installs, and offers to restart.
- Or in Konsole: `sudo sufun-update ~/Downloads/sufun-update-1.1.sufun`
- **Refused with a Korean message:** unsigned or wrongly signed files, a revoked/expired key, damaged files (checksum), unexpected contents, an older or the same version, or a too-old installed version. Internet is needed, because the Arch packages are updated in the same step (no half-updated system).

**.sufun file contents:** `manifest` (version, minimum version, build time), `notes.ko.txt`, `packages/` (sufun-base, sufun-keyring and our other packages, each with a `.sig` signature), `SHA256SUMS` and `SHA256SUMS.sig` (signed).

---

## 서명 키 관리 (item 24, 꼭 읽으세요)

SUFUN 업데이트 파일은 **서명**되어 있어서, 다른 사람이 가짜 업데이트를 만들 수 없습니다. 서명에는 키 두 개를 씁니다.

| 키 | 하는 일 | 보관 장소 |
|---|---|---|
| **기본 키 (primary)** | 서명 키를 만들고, 연장하고, 취소하는 "도장" | **오프라인 USB에만.** GitHub, 클라우드, 이 PC에 두지 않습니다 |
| **서명 하위 키 (subkey)** | 릴리스 파일에 서명. **2년 후 만료** | GitHub의 `release` 환경 비밀값(secret) |

공개 키(`keys/sufun.asc`)는 `sufun-keyring` 패키지에 들어 있어서, 나중에 업데이트로 새 키를 추가하거나 옛 키를 취소할 수 있습니다.

**처음 한 번: 키 만들기**
1. Git Bash 창을 직접 열고 (AI 도구로 실행하지 마세요: 암호를 입력해야 합니다):
   ```bash
   cd "/c/Surface go 3 OS"
   bash scripts/sufun-key.sh create E:/SUFUN-KEY      # E: = 백업용 USB
   ```
   강력한 암호(passphrase)를 정하세요. 잊어버리면 키를 쓸 수 없습니다.
2. 화면에 나오는 `gh secret set ...` 명령 두 개로 GitHub에 서명 하위 키와 암호를 올립니다. (`gh`는 https://cli.github.com 에서 설치, `gh auth login` 먼저)
3. `keys/sufun.asc`(공개 키)를 커밋하고 push합니다.
4. USB(`E:/SUFUN-KEY`)는 **클라우드에 올리지 말고** 안전한 곳에 보관하세요. 가능하면 USB 두 개에 복사해 두세요.

**GitHub 설정 (한 번)**
- GitHub 계정에 **2단계 인증(2FA)**을 켜세요: *Settings → Password and authentication → Two-factor authentication*.
- 저장소 *Settings → Environments → New environment* → 이름 `release`:
  - *Required reviewers*에 본인 추가 (릴리스 전에 승인 필요)
  - *Deployment branches and tags* → *Selected* → **Tag** 규칙 `v*`
  - ⚠️ 무료 요금제에서 승인(Required reviewers)과 환경 비밀값은 **공개(public) 저장소에서만** 됩니다. 비공개(private)로 쓰려면 GitHub Pro가 필요합니다.
- 비밀값은 `release` 환경에만 있으므로 일반 push, pull request, fork에서는 절대 쓸 수 없습니다.

**만료 전에 연장하기 (2년마다, 만료 1~2달 전)**
```bash
bash scripts/sufun-key.sh extend E:/SUFUN-KEY
```
그다음 새 `sufun-signing-subkey-for-github.asc`를 `gh secret set`으로 다시 올리고, `keys/sufun.asc`를 커밋한 뒤 새 버전을 릴리스하세요. (사용자들이 새 만료일을 받도록)

**서명 하위 키가 유출되었을 때** (예: GitHub 계정이 해킹됨)
1. 바로 GitHub 암호를 바꾸고 `release` 환경의 비밀값을 삭제하세요.
2. `bash scripts/sufun-key.sh rotate E:/SUFUN-KEY` → 옛 하위 키를 **취소**하고 새 하위 키를 만듭니다.
3. 새 하위 키를 `gh secret set`으로 올리고, `keys/sufun.asc`를 커밋하고, **바로 새 버전을 릴리스**하세요. 그 업데이트가 취소 정보를 사용자에게 전달합니다. 그 후에는 유출된 키로 서명한 파일이 모두 거부됩니다.

**기본 키(USB)를 잃어버렸을 때**
- 지금 서명 하위 키는 만료일까지는 계속 쓸 수 있습니다. 그 전에 새 키를 준비하세요.
- `create`로 **새 키**를 만들고, 옛 키와 새 키를 둘 다 `keys/sufun.asc`에 넣은 `sufun-keyring`을 **옛 하위 키로 서명한 업데이트**로 배포하세요. 그 다음 릴리스부터 새 키로 서명합니다.
- 옛 하위 키도 이미 만료됐거나 쓸 수 없다면: 사용자들은 **새 ISO로 다시 설치**하거나, 새 `sufun-keyring` 패키지를 직접 받아 `sudo pacman -U sufun-keyring-*.pkg.tar.zst`로 설치해야 합니다. (이때는 GitHub Release의 SHA256 값을 직접 확인하세요.)
- 기본 키를 **도난**당했다면: 그 기본 키 지문을 `keys/sufun-revoked`에 적고, 새 키로 위 과정을 하세요.

---

## UEFI 암호 (item 27, 디스크 암호화 대신)

SUFUN은 디스크를 암호화하지 않습니다. 대신 **Surface UEFI 암호**로 기기를 보호합니다. **SUFUN 설치가 끝난 뒤에** 설정하세요. (먼저 설정하면 설치용 USB로 부팅할 수 없습니다.)

1. Surface를 끕니다. **볼륨 올리기(+) 버튼을 누른 채로 전원 버튼을 눌렀다 떼고**, UEFI 화면이 나올 때까지 볼륨 버튼을 계속 누릅니다.
2. **Security** 페이지 → **Password**: UEFI 암호를 설정합니다. (6자 이상, 대소문자 구분)
3. **Boot configuration** 페이지:
   - **USB Storage**를 끕니다 (USB 부팅 금지).
   - 내부 드라이브(Internal Storage / SUFUN)가 맨 위에 오게 순서를 정합니다.
   - 순서를 바꿨다면 **Enable Alternate Boot Sequence**가 켜져 있어야 적용됩니다.
4. **Exit → Restart Now**.
(메뉴 이름은 Microsoft 문서 기준입니다. 가정용 Surface Go 3에는 Devices, Management 페이지가 없습니다.)

**보호되는 것:** 암호 없이는 아무도 USB로 다른 운영체제를 부팅하거나 UEFI 설정(Secure Boot, 부팅 순서 등)을 바꿀 수 없습니다.
**보호되지 않는 것:** 이것은 **암호화가 아닙니다.** eMMC 칩을 직접 떼어 내는 것 같은 하드웨어 공격은 막지 못합니다. 그리고 SUFUN 로그인 암호는 여전히 필요합니다.

> ⚠️ **UEFI 암호를 꼭 적어서 안전한 곳에 보관하세요.** Microsoft는 "UEFI 암호는 재설정할 수 없고, Microsoft도 알아낼 수 없다"고 안내합니다. 잊어버리면 Microsoft 서비스(기기 교체/수리)를 받아야 할 수 있습니다.

나중에 USB로 부팅해야 할 때 (Timeshift 복원, 재설치): UEFI에 들어가 암호를 입력하고 **USB Storage**를 다시 켜세요. 작업이 끝나면 다시 끄세요.

---

## Steam 안내 (item 28)

- **Proton**은 Windows 게임을 Linux에서 실행하는 Steam의 도구입니다. 모든 게임에 켜기: Steam → **설정 → 호환성 → "지원되는 모든 타이틀에 Steam Play 활성화"** (+ 최신 Proton 선택) → Steam 재시작.
- 게임을 사기 전에 **ProtonDB** (https://www.protondb.com)에서 게임 이름을 검색하세요. Platinum/Gold면 대체로 잘 됩니다.
- **이 기기에서 현실적으로 되는 게임:** 2D 게임, 인디 게임, 오래된 3D 게임 (대략 2015년 이전, 낮은 그래픽 설정). 최신 3D 대작은 CPU(2코어)와 내장 그래픽(UHD 615) 때문에 어렵습니다.
- **RAM 절약 설정 (4 GB):**
  - Steam → 설정 → **인터페이스**: "Steam 시작 시 표시할 창" → **라이브러리**, "부드러운 스크롤/GPU 가속 웹 보기" 끄기
  - 설정 → **게임 중**: Steam 오버레이 끄기
  - 설정 → **다운로드/셰이더 사전 캐싱**: 셰이더 사전 캐싱 끄기 (디스크와 CPU 절약)
  - 게임 실행 중에는 Firefox 등 다른 프로그램을 닫으세요.
- Steam 창을 닫으면 Steam이 **완전히 종료**됩니다 (게임 실행 중에는 종료하지 않음). 로그인할 때 Steam이 자동으로 켜지지 않습니다.
- ⚠️ **커널 안티치트 게임은 Linux에서 안 됩니다:** 예) **리그 오브 레전드, 발로란트** (Riot Vanguard). 배틀그라운드 등 일부 온라인 게임도 마찬가지입니다. https://areweanticheatyet.com 에서 확인하세요.

---

## Automatic boot and install test (item 25)

Every build (test builds and releases) is boot-tested in a virtual machine (QEMU + UEFI firmware), like KDE Linux does:
1. **Live USB** boots to the Plasma desktop and checks the Windows 11-style layout (start menu, search box, Task View, clock, tray, Win+A/Win+N, desktop icons, SUFUN start logo, no Microsoft logos) and prints RAM numbers (`INFO ram ...`).
2. **Installer** runs in a test-only automatic mode and installs to an empty 64 GB virtual disk. This mode runs only when **all three** are true: `SUFUN_AUTO=1`, the kernel option `sufun.test=install`, and the computer is a QEMU VM. So it can never start on your Surface.
3. **Installed system** boots from the virtual disk and checks itself: SUFUN boot entry, `splash` and the Plymouth theme in the initramfs, login screen shown, `sufun-base` version = `VERSION`, zram, earlyoom and firewall active, no `subvolid` in fstab, Timeshift config, os-release. After the login-screen screenshot it logs the test user in automatically (**test disk only**: the autologin file is written by the test itself, a real install never has it) and checks the **Korean** desktop: Korean folder names (바탕화면, 문서, 다운로드), taskbar, tray, desktop icons.

Only in test mode, the installed system's boot options also get `plymouth.ignore-serial-consoles` (with the test's serial console, Plymouth would show text instead of the SUFUN splash). A real install's boot options are unchanged.

Results come from the virtual serial port, not from fixed waiting times. Screenshots and serial logs are uploaded as the **sufun-test-results** artifact. Screenshots are taken every 10 seconds for the first 3 minutes of each virtual PC, then every minute; the file name tells the time since power-on, e.g. `3-installed-t0040.png` = 40 s. KVM is used when the runner has it, otherwise slow software emulation with 4× longer time limits. **Releases are only signed if all tests pass.**

> The VM has no Surface hardware. **Touch, pen, cameras, Type Cover, lid, rotation and sleep must still be tested on the real device**: see the first-boot checklists in the camera, Korean input, lid and keyboard sections above.

---

## Checking the AUR for updates (item 26)

Our copies of AUR packages never change by themselves. To see whether the AUR has newer versions:
```bash
bash scripts/check-aur-updates.sh            # all packages
bash scripts/check-aur-updates.sh bottles    # just one
```
For each package with a newer AUR version it prints the **full diff** (our copy vs the AUR), plus what to look for: new download URLs, new commands in `build()`/`package()`, new install scripts. If it looks fine, copy the new PKGBUILD into `packages/pkgbuilds/<name>/`, keep our two header lines, replace any `SKIP` checksum with a real one, and push (the CI builds and tests it).
Currently all copies match the AUR. Note: H2Orestart upstream already released 0.8.0 (the AUR is still at 0.7.13).

---

## Later step: CachyOS x86-64-v3 repository (not done yet)

After the first boot, run:
```bash
/lib/ld-linux-x86-64.so.2 --help | grep x86-64-v
```
Only if it prints `x86-64-v3 (supported, searched)` should the CachyOS v3 repo be added. AVX2 is confirmed on this CPU, but v3 also needs FMA, BMI1/2, F16C, LZCNT and MOVBE; the command checks them all. (CachyOS has no v2 repo.)

---

## 1. Build the ISO

### Option A: GitHub Actions (easiest from Windows)
1. Create a GitHub repo and push this folder to it (branch `main`).
2. The **Build ISO (test)** workflow starts by itself on every push (don't start it a second time by hand).
3. After about 1–2 hours (build + tests), download `sufun-iso` from the run page.

### Option B: Locally with WSL
```powershell
wsl --install -d archlinux
```
Then inside WSL:
```bash
cd "/mnt/c/Surface go 3 OS" && sudo bash build.sh     # ISO ends up in out/
```
Note: building also installs the build tools inside your WSL Arch.

## 2. Write it to a USB drive
Use [Rufus](https://rufus.ie) in **DD image** mode, or copy the ISO onto a [Ventoy](https://www.ventoy.net) stick.
The Surface Go 3 has a single USB-C port, so you need a USB-C stick or an adapter.

## 3. Boot it on the Surface Go 3
1. **Disable Secure Boot**: power off, hold **Volume Up** and press **Power** to open Surface UEFI, go to *Security → Secure Boot → Disabled*.
2. Plug in the USB, then hold **Volume Down** and press **Power** to boot from USB.
3. The live desktop starts automatically. Connect to Wi-Fi from the taskbar.

## 4. Install
Double-click **Install SUFUN** (or run `sudo sufun-install` in Konsole).

> ⚠️ This **erases the whole internal drive, Windows included**. Back up first. Before you start, you can download a Surface Go 3 recovery image from Microsoft so you can restore Windows later.

Afterwards: set the UEFI password (see "UEFI 암호").

## Hardware status (linux-surface on Go 3)
| Works | Partial / not working |
|---|---|
| Wi-Fi, Bluetooth, touchscreen, Surface Pen, Type Cover, audio, battery, suspend (s2idle), auto-rotate, brightness, USB-C display, **front and rear cameras** (libcamera) | IR camera (face login); waking by opening the lid is unconfirmed (power button always works); rare suspend hangs reported |

## Customising
- Add or remove apps: edit `packages/desktop.txt` (official) and rebuild. Release a new version so installed systems get it.
- Our own packages (Selawik, ananicy rules, H2Orestart, Bottles) don't update with `pacman -Syu`; they come with `.sufun` updates.

## Known risks (not yet tested on real hardware)
The ISO is built and boot-tested in GitHub Actions (virtual machine), but not yet on a real Surface Go 3. Most likely to need a fix on real hardware:
- The Windows 11-style taskbar at 150% scale on the real 10.5" screen (sizes were chosen for 150%).
- Building the pinned packages in CI (and Bottles once it is switched back on).
- The Plasma layout script and theme names (if wrong, Plasma falls back to the normal KDE look; nothing breaks).
- The first CI boot tests themselves (timeouts, the login-screen detection).
- Plymouth → SDDM hand-over (`--retain-splash`); if the login screen doesn't appear, delete `/usr/lib/systemd/system/sddm.service.d/50-sufun-plymouth.conf`.
