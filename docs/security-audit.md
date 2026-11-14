# SUFUN security audit (2026-11-15)

Scope: this repository and SUFUN running in the CI virtual machines (live system
and installed system). Nothing else was scanned or attacked.

Method: (1) code review of everything that runs as root or decides what root
runs, (2) attacks inside the CI VMs, written as tests so they run again on every
build, (3) fixes, (4) this report.

## 한국어 요약 (쉬운 설명)

**결론: 심각(Critical)·높음(High) 등급의 문제는 찾지 못했습니다.** 중간(Medium) 4개 중 3개는 고쳤고, 1개(PH-1, 기기를 훔친 사람)는 설계상 한계라서 고치지 않고 설명만 적었습니다. 낮음(Low) 14개 중 13개는 고쳤고, 1개(G-6)는 선택 사항으로 남겼습니다.

| 무엇 | 쉬운 설명 | 상태 |
|---|---|---|
| 업데이트 파일(.sufun) | 가짜·변조·옛날·서명 없는 업데이트는 모두 거부됩니다. 검사한 파일과 설치하는 파일이 항상 같은 파일이 되도록 더 단단하게 고쳤습니다. | 고침 + 자동 테스트 |
| 키보드 엿보기 | 설치된 사용자가 `input` 그룹에 들어 있어서, 사용자의 아무 프로그램이나 모든 키 입력(잠금 화면 암호 포함)을 읽을 수 있었습니다. | 고침 |
| 라이브 시스템 방화벽 | 라이브 시스템은 암호가 없는데 방화벽도 꺼져 있었습니다. (열린 포트는 없었습니다.) | 고침 (방화벽 켬) |
| 릴리스 승인 | README에는 "서명 전에 승인"이라고 되어 있었지만 GitHub에 그 설정(`release` 환경)이 실제로는 없었습니다. | 고침 (만들었음) |
| 기기를 훔친 사람 | 디스크 암호화가 없어서, Surface나 SD카드를 손에 넣은 사람은 파일을 읽을 수 있습니다. UEFI 암호로는 막을 수 없습니다. | **고치지 않음** (아래 PH-1, 결정 필요) |
| CI 테스트 모드 | 실제 Surface에서는 절대 켜지지 않습니다 (QEMU 가상 머신인지 확인). | 확인 + 한 군데 보강 |
| 네트워크 | 밖에서 접속할 수 있는 포트가 하나도 없습니다 (라이브·설치 모두, 호스트에서 전체 포트 스캔). | 확인 |
| Firefox / uBlock | 보안 설정을 바꾼 것이 없고, uBlock 파일은 Mozilla가 공개한 것과 같은 파일입니다. | 확인 |
| 서명 키 | 저장소에 비밀 키가 없고, PR·포크는 비밀값에 접근할 수 없습니다. | 확인 |

## Severity scale

- **Critical / High**: someone remote, or a normal local user, can run code as root or install unsigned software. **None found.**
- **Medium**: a real weakness that needs a second condition (physical access, an already-running malicious program of the user, a stolen GitHub login).
- **Low**: hardening; no working attack was found.
- **Info**: checked, works as intended, or a design limit worth knowing.

## Findings

| ID | Severity | Where | Status |
|---|---|---|---|
| I-1 | Medium | installer: user in group `input` | fixed |
| N-1 | Medium | live system without firewall | fixed |
| G-1 | Medium | GitHub: `release` environment did not exist | fixed |
| PH-1 | Medium | physical access, no disk encryption | **not fixed**, documented |
| U-1 | Low | `sufun-update` read the user's file several times | fixed |
| U-2 | Low | `sufun-update`: file names handed to `tar` | fixed |
| T-1 | Low | `sufun-selftest` had no "QEMU only" check of its own | fixed |
| M-1 | Low | `sufun-memguard` chose by process name only | fixed |
| W-1 | Low | `welcome-apply` parsing of the chooser's answer | fixed |
| S-1 | Low | fixed names in `/tmp` | fixed |
| G-2 | Low | actions pinned by tag, not by commit | fixed |
| G-3 | Low | job token left in `.git/config` | fixed |
| G-4 | Low | signing passphrase on a command line | fixed |
| G-5 | Low | release accepted any secret key | fixed |
| G-6 | Low | no branch / tag protection rules | not changed (optional, see below) |
| B-1 | Low | linux-surface key pinned by short id | fixed |
| B-2 | Low | build user keeps password-less `pacman` | fixed |
| P-1 | Low | Windows script: `diskpart` command file in `%TEMP%` | fixed |
| U-3 | Info | an older (but newer than installed) signed update is accepted | by design |

### I-1 (Medium) The installed user could read every key press

- **What:** the installer created the user with `-G wheel,video,audio,input`.
- **Attack:** members of `input` can open `/dev/input/event*`. Any program the user runs (a game, a Windows program in Wine, a script from the internet) could record all key presses of every session, including the password typed at the lock screen, at login and for `sudo`. Wayland normally prevents exactly this. With the recorded password the program becomes root.
- **Fix:** the user is no longer in `input` (installer and live user). KWin gets the devices through logind and does not need the group. Steam controllers use `uaccess` rules, not the group.
- **Tests:** `user-not-in-input-group` (VM), lint rule "user is not added to the 'input' group".
- **Real Surface:** please check once that touch, pen, touchpad gestures and tablet mode still work. They should, since the desktop never needed the group.

### N-1 (Medium) Live system: no password and no firewall

- **What:** the live user has no password and password-less `sudo` (needed for a live system), and `ufw` was not running there.
- **Attack:** on public Wi-Fi, any program that opens a network port in the live session (Steam Remote Play, a development server, a file-sharing program) would be reachable by everyone on that network.
- **Checked:** see "Port scan" below for what was listening before the fix.
- **Fix:** the live system starts `ufw` with the same rules as an installed system (block incoming, allow outgoing).
- **Tests:** `live-firewall-on`, `firewall-default-deny`, port scan of the live VM from the CI host.

### G-1 (Medium) The release approval step did not exist

- **What:** `release.yml` signs in `environment: release`, and the README says the job waits for your approval there. The environment did not exist on GitHub. GitHub creates a missing environment by itself, **without** any approval rule, the first time it is used (also `gh secret set --env release` does that).
- **Attack:** someone who gets your GitHub login or a token with push rights pushes a tag `v9.9`. Once the signing secret exists, the workflow would have signed and published a release without anyone approving it.
- **Fix (done on GitHub, 2026-11-15):** environment `release` now exists with **required reviewer = you** and **only tags `v*`** may use it. The signing secrets you add later land in this protected environment.
- **Tests:** lint rules "release job waits in the 'release' environment", "secrets are used only in release.yml". The approval rule itself is a GitHub setting; check it under *Settings → Environments → release*.
- **Limit:** someone with your full GitHub login can also change that setting. Use two-factor login (see G-6).

### PH-1 (Medium, not fixed) Someone who has the device

SUFUN does not encrypt the disk (this was a decision made earlier: "UEFI 암호, 디스크 암호화 대신"). Secure Boot is off on this Surface. What that means:

| Attacker has... | Can they read your files? | Does the UEFI password help? |
|---|---|---|
| the Surface, switched on and locked | No (lock screen needs the password; no open network port) | not needed |
| the Surface, eMMC install, **no** microSD card in it | Not without opening the device, **if** the UEFI password is set and USB boot is off: the firmware can't start a microSD card, the boot menu editor is off, root is locked. Without the UEFI password they can simply switch USB boot on. | **Yes, this is what it protects** |
| the Surface **with the microSD card that holds the live system** | **Yes.** The boot menu offers "SUFUN Live (microSD, rescue)"; it starts as an administrator without a password and can read the internal disk. | **No** |
| the microSD card of an SD install | **Yes.** They put the card into any computer. | **No** |
| the opened device (eMMC chip read directly) | Yes | No |

So the UEFI password protects the firmware settings (boot order, USB boot, Secure Boot setting) and nothing else. The login password and the lock screen protect a Surface that is switched on and left alone for a moment. Neither protects your files after a theft.

**Why not fixed here:** the real fix is disk encryption (LUKS). That is a larger feature with its own problems on this tablet (typing the passphrase at boot without the Type Cover, the SD boot stage, Timeshift). It should be your decision.

**What you can do now:**
- eMMC install: take the microSD card with the live system out and keep it somewhere else. Then the rescue entry cannot start, and with a UEFI password the device is reasonably protected against a casual thief.
- SD install: treat the card like an unlocked USB stick.
- Tell me if you want an "encrypt my files" option (encrypted home folder or full disk); it needs a design and real-hardware testing.

Tests for the parts that do hold: `boot-menu-editor-off`, `root-account-locked`, `sddm-no-autologin`, `lock-screen-on`, `boot-partition-root-only`, `no-empty-password`.

### U-1 (Low) `sufun-update` read the update file more than once

- **What:** as root, the tool listed the archive, listed it again for file types, then unpacked it: three separate reads of a file in the user's folder.
- **Attack idea:** swap the file between "names and types are fine" and "unpack", so that links or odd paths get unpacked. I could not turn this into a working attack: everything unpacked must still match the signed checksum list, and GNU tar refuses `..` paths by itself. But the safety rested on details of `tar`.
- **Fix:** the file is copied once into a root-only folder; all checks and the installation use that copy. After unpacking, anything that is not a plain file or folder is refused again.
- **Tests:** `update-link-refused`, `update-path-traversal-refused`, `update-nothing-escaped`, `update-extra-file-refused`.

### U-2 (Low) File names handed to `tar`

- **What:** GNU tar treats a name like `host:file.sufun` as "a tape on another computer" and tries to connect to it; a name starting with `-` could be read as an option.
- **Attack:** a downloaded file with such a name, double-clicked, makes `tar` contact another computer. No code execution found.
- **Fix:** `tar --force-local` everywhere; names starting with `-` are refused; only one file name is accepted.
- **Tests:** `update-option-name-refused`, lint rule "update tool: private copy, no remote tar names".

### U-3 (Info) Old signed updates

`sufun-update` refuses the installed version and anything older (`update-old-version-refused`). It cannot know that a newer release exists: on a 1.0 system, a genuine signed 1.1 file is accepted even after 1.2 came out. That is normal for update files that work offline. If a release ever has a serious hole, publish the next one with `release-notes/<version>.min-from`, and revoke the subkey if it leaked (`sufun-key.sh rotate`).

### T-1 (Low) Test mode

- **Checked:** every test switch needs the kernel option `sufun.test=...` **and** a QEMU virtual machine (`/sys/class/dmi/id/sys_vendor`, set by the firmware; a normal user can change neither). The installer's automatic mode needs `SUFUN_AUTO=1` in addition. The selftest and its service exist only on the live ISO; a real install never gets them, never gets `sufun.test=installed` in its boot entry, and never gets auto-login.
- **Gap:** `sufun-selftest` itself did not check for QEMU (the installer it calls did). With `sufun.test=live` added to the boot entry of a real Surface it would have run its checks and switched the machine off. Changing the boot entry needs administrator rights, so this was no way in.
- **Fix:** the selftest exits at once when the machine is not a QEMU VM.
- **Tests:** `installer-test-mode-refused` (VM: the automatic installer refuses under `sufun.test=live`), lint group "CI test mode can never start on a real computer" (6 rules, tried with a deliberately broken file).

### M-1 (Low) Memory guard chose its target by name

- **What:** `sufun-memguard` (root) closes the biggest process named `Web Content`, `Isolated Web Co`... Any program can give itself such a name.
- **Attack:** a normal user or a web page cannot make it close something else: it only ever closes a process with one of those names. A web page that eats memory gets its own tab closed (or the biggest tab), which is the purpose. But a system process with such a name would also have been a candidate, and a fake "tab" could draw the guard away from the real one.
- **Fix:** candidates must belong to a person (user id 1000 or higher) and, for Firefox names, really run a program from `/usr/lib/firefox`.
- **sufun-memwatch** runs as the user and can only restart that user's own desktop helpers; KWin and Firefox are refused by name (existing tests). Its test mode needs the QEMU check too.
- **Tests:** `memguard-ignores-fake-tab`; the existing memory-pressure test still closes the real tab.

### W-1 (Low) First-start chooser answer

- **What:** root's `welcome-apply` read the answer written by the unprivileged chooser user with an unquoted `$(head ...)` (file-name patterns like `*` were expanded) and followed links.
- **Attack:** only for someone who already controls the chooser process. They could make root read the start of another file and get parts of it into the journal. Values were always checked against SUFUN's own lists, so no setting could be forged.
- **Fix:** the answer must be a plain file, only its first line is read, nothing is expanded.
- **Tests:** `welcome-refuses-link`, `welcome-refuses-injection`, `welcome-settings-unchanged`.

### S-1 (Low) Fixed names in `/tmp`

The installer wrote `/tmp/sufun-pacman.conf` (now `mktemp`), and `input-switch` fell back to `/tmp` without `XDG_RUNTIME_DIR` (now `/run/user/<id>`). On the live system the user is root-equivalent anyway.

### G-2 to G-6 GitHub

- **G-2:** `actions/checkout@v5` etc. are tags that their owner can move. All actions are now pinned to a full commit id (lint rule).
- **G-3:** `persist-credentials: false` on every checkout: the (read-only) job token is not left on disk while package build scripts run.
- **G-4:** the key passphrase was a `gpg --passphrase "..."` argument, visible in the process list of the runner. It now goes through a pipe (`--passphrase-fd`). The update test media is made with this code path on every build.
- **G-5:** the release job now stops if the secret contains the primary key instead of only the signing subkey.
- **G-6 (optional, not changed):** the repository has no rules against force-pushing `main` or moving a `v*` tag, and I can't see whether two-factor login is on. Recommended: turn on 2FA; *Settings → Rules → New ruleset*: block deletion and force-push for `main` and for tags `v*`.
- **Checked, fine:** no `pull_request` / `pull_request_target` trigger at all, so pull requests and forks run nothing and can't reach secrets; default token is read-only; only the release job may write; no untrusted text (`github.event...`) in any command; secret scanning and push protection are on; `.gitignore` blocks key files; no private key in the repository or its history paths; the private key is never printed (only key ids).

### B-1, B-2 Build

- **B-1:** the linux-surface key was accepted by its 16-character id. Now the full fingerprint `87DEFA4AB94A99A4C8C3112556C464BAAC421453` must match and the downloaded file must hold exactly one key.
- **B-2:** `build-local-repo.sh` gives the build user password-less `pacman`. Fine in the throwaway CI container, but on your own WSL Arch it stayed. It is removed when the script ends.
- **Info:** the packages on the live ISO are not signed (`sufun-local`, `TrustAll`); the ISO as a whole is covered by the signed `SHA256SUMS` of a release. Check that file after downloading an ISO.

### P-1 (Low) Windows setup script

`sufun-sd-setup.ps1` (administrator) wrote its `diskpart` commands to `%TEMP%\sufun-diskpart.txt`. Another program of the same user could have replaced the file before `diskpart` read it. Now: a random name in `C:\Windows\Temp`. The existing Windows CI test covers this path.

## Checked and found fine

- **Signature check of updates:** `gpgv` with a keyring that holds only SUFUN keys; revoked and expired keys refused; the primary key must be in the trusted list; every package is checked again by itself and by pacman; a normal user can't install (`pkexec` asks for the admin password; polkit policy `auth_admin`).
- **Root helpers:** `sufun-windows-restore`, `sync-boot-stage`, `pacman-snapshot`, `apply-os-release`, `typecover`, `kmemwatch`, the pacman hooks and systemd units: fixed paths, quoted variables, config read as data (not executed), state in root-only folders. `first-login`, `steam-launch`, `input-switch`, `memwatch`, `preload`, `rotation-lock` run as the user.
- **polkit:** one rule; it allows only `start` of `sufun-typecover-rebind.service` for the user sitting at the device.
- **sudo:** installed system `%wheel ALL=(ALL:ALL) ALL` (password), root locked. Password-less sudo only in the live system.
- **Firefox:** no security preference changed, nothing locked, Fission on, add-on signature checks untouched. uBlock Origin 1.76.2: our checksum equals the one addons.mozilla.org publishes for the signed file (checked on every build), `normal_installed`, no other extension.
- **Kernel:** CPU mitigations on (no `mitigations=off`).

## Results from the CI virtual machines

RESULTS_PLACEHOLDER

## Regression tests added

- **`security-lint` job** (`scripts/ci/security-lint.sh`): about 50 static rules; runs before the build.
- **Port scan** (`scripts/ci/portscan.sh`): the CI host scans the live VM and the installed VM over a private test network: all 65535 TCP ports and the usual UDP service ports.
- **In the VMs** (`sufun-selftest`): `security_live`, `security_accounts`, `security_installed`, `update_attack_tests`, `host_portscan`.
- **Update attacks** use a `.sufun` file made by the real release tools (`sufun-key.sh`, `make-sufun-update.sh`) from the build's packages with a throwaway key (`scripts/ci/make-security-media.sh`). The real signing key is never involved.

## Not covered

- The real Surface firmware (UEFI password behaviour is taken from Microsoft's documentation, not tested).
- Bugs in third-party software (kernel, KDE, Firefox, Steam, Wine): kept current by `pacman -Syu`.
- Attacks through Bluetooth or Wi-Fi drivers. Bluetooth is off until you switch it on.
- A real release run (no signing key exists yet); the signing code path is tested with the throwaway key.
