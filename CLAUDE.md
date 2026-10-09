# CLAUDE.md

Guidance for Claude Code in this repository. Keep it and `README.md` current: update both whenever a file, a decision or a procedure changes, not at the end. `README.md` is for humans, in French; this file is for agents.

## What this is

A bootc image for Claire's Framework 13 AMD (Ryzen AI 300): `FROM ghcr.io/ublue-os/aurora:stable` (Fedora Atomic, KDE Plasma) plus a few settings. Claire is not technical: she only uses the desktop and the Bazaar store. The user (Gabriel) administers the machine remotely over Tailscale SSH, with his own admin account `gaugendre`.

Sibling repos, same owner:
- `~/Projects/codeberg.org/Crocmagnon/arch-config`: his Arch machines (decman). Framework-specific settings come from there; read its `CLAUDE.md` and `decman/framework_gab_amd.py` before adding hardware tweaks.
- `nixos-config`: srv-1. Never touch it.

## How it ships

- `.github/workflows/build.yml` builds on every push to `main`, nightly (03:05 UTC; GitHub may delay scheduled runs) and on pull requests. PRs build but never publish. Changes touching only `*.md`, `.github/renovate.json` or `LICENSE` trigger nothing (`paths-ignore`, a YAML anchor shared by `push` and `pull_request`): keep that list to files that never reach the image.
- On `main`, it pushes `ghcr.io/crocmagnon/aurora-claire:latest` and signs it with cosign (secret `SIGNING_SECRET`; public key `cosign.pub`).
- The laptop runs `bootc switch`ed to that image. uupd stages updates; they apply at next reboot.
- **A push to `main` is a deployment to Claire's laptop.** Prefer a branch + PR, and never push to `main` without the user's go.

## Layout

| Path | Role |
|---|---|
| `Containerfile` | `FROM aurora:stable` (no digest, on purpose), runs `build.sh`, then `bootc container lint` |
| `build_files/build.sh` | Copies `system_files/` to `/` (owned by root), installs packages, patches the PAM autologin file |
| `system_files/` | Copied as-is to the image root |
| `system_files/usr/lib/aurora-config/` | Our own files that are not config of another package (GRUB `custom.cfg`; the GRUB theme is added there at build) |
| `image-template.env` | `IMAGE_NAME=aurora-claire` (differs from the repo name so more images can be added) |
| `Justfile` | Template's build recipes, used by CI. Left as upstream to ease template merges |
| `disk_config/` | Unused (ISO builds were removed); kept because `Justfile` references it |
| `.github/renovate.json` | Renovate, same style as the user's other repos (`config:recommended`, monthly). Only the `github-actions` manager: the Dockerfile manager would pin `FROM aurora:stable` to a digest and freeze the base. Dependabot was removed |

## Rules

- **Put config under `/usr/lib` (or `/usr/share`) rather than `/etc`.** `/etc` gets a three-way merge: a locally modified file masks the image forever. Use `system_files/etc/` only when the software reads nothing under `/usr` (none today).
- **Kernel args go in `system_files/usr/lib/bootc/kargs.d/*.toml`**, one file per topic. bootc applies them on switch and upgrade.
- **Patch package-owned files in `build.sh` instead of copying them**, and make the build fail if the anchor disappears (see the PAM `sed` + `grep`). A copied file would silently drift from Fedora's.
- **Cite the origin** in a comment when a setting comes from `arch-config` or nixos-hardware.
- **Changing dracut config requires regenerating the initramfs in `build.sh`.** Aurora builds it in `build_scripts/base/19-initramfs.sh` (ublue-os/aurora): copy that command, including its os-release handling.
- **Secrets never go in the image or the repo in clear.** If one must be versioned, use git-crypt. The cosign private key exists only as the GitHub secret; regenerate rather than store it.
- **Build locally before pushing:** `docker build -f Containerfile -t localhost/aurora-claire .` (needs `docker-buildx` for `RUN --mount`; no podman on the host). It runs `bootc container lint` too. `docker pull ghcr.io/ublue-os/aurora:stable` first to test against the latest upstream. CI stays the source of truth (`gh run watch`, `gh run view --log-failed`).
- **Never let `system_files/` ownership leak into the image.** `build.sh` copies with `--no-preserve=ownership`: a plain `cp -a` from a bind mount (or a future build method that preserves source ownership) makes `/etc`, `/usr` and our files owned by uid 1000, which is Claire on the laptop. In CI, `COPY` already gives root, but do not rely on it. Check with `find / -xdev -uid 1000` in the built image.
- **Inspect upstream Aurora** with `docker run --rm ghcr.io/ublue-os/aurora:stable …` (pulled locally) or its sources (`gh repo clone ublue-os/aurora`).
- **Comments, docs and commit messages are in French**, like the sibling repos.

## Facts about upstream Aurora (verified in its sources, October 2026)

- Display manager is **plasma-login-manager** (`plasmalogin.service`), same as `arch-config`.
- Preset-enabled: `tailscaled.service`, `uupd.timer`, `flatpak-preinstall.service`. Flatpak's `preinstall.d` is supported; Aurora itself ships `bazaar.preinstall`.
- Removed on purpose: `plasma-discover`, the `firefox` RPM, `fedora-flathub-remote`. The store is Bazaar; Firefox is a Flatpak.
- The initramfs is generic, built at image build time: it does not read the machine's `/etc/vconsole.conf`. The installer compensates by adding the chosen keymap as a karg (`vconsole.keymap=fr-oss`), so we ship none.
- ublue LUKS dracut config adds `fido2 pkcs11 pcsc`.
- PAM files live in `/usr/lib/pam.d/` (no copy in `/etc/pam.d/`). Fedora's `plasmalogin-autologin` calls `pam_kwallet5` only in the `session` phase; `plasmalogin` (password login) also calls it in `auth`. `build.sh` therefore inserts `pam_systemd_loadkey` then `-auth pam_kwallet5` before `auth include postlogin`. `pam_systemd_loadkey.so` and `pam_kwallet5.so` (package `pam-kwallet`) are both present.
- plasma-login-manager reads `/usr/lib/plasmalogin/plasmalogin.conf.d/` (shipped empty by the package) and `/etc/plasmalogin.conf.d/`; `/etc/plasmalogin.conf` is all comments. Autologin session file is `/usr/share/wayland-sessions/plasma.desktop` (`Session=plasma`).
- The Aurora ISO (`aurora-stable-webui-x86_64.iso`, 7 GB, version 44.20260908 on 2026-10-09) installs offline from its embedded image (no network traffic during « Installation des logiciels »); the deployed system then tracks `ghcr.io/ublue-os/aurora:stable`. The MOK enrollment screen is always QWERTY (type `universqlblue` on AZERTY). The first LUKS prompt, before switching to our image, already follows the installer's keyboard choice (verified 2026-10-09 with an AZERTY-sensitive passphrase). The installer lets you pick the keyboard (default `fr (oss)`, same letters and digits as `fr`) but creates no user: the account is created by a first-boot wizard. Default partitioning: `/boot/efi`, `/boot` ext4 (clear), one LUKS btrfs partition with `/`, `/home`, `/var` subvolumes; swap is zram.
- `fuse-libs` is already in Aurora; `steam-devices` and `hunspell-fr` come from Fedora repos. Kept explicit in `build.sh` to document why they matter.

## Verified in the VM (2026-10-09)

- Autologin works from `/usr/lib/plasmalogin/plasmalogin.conf.d/autologin.conf`.
- The wallet unlocks at autologin with the LUKS passphrase under Fedora's dracut initramfs and SELinux: the PAM audit line lists `pam_systemd_loadkey` among grantors, `pam_kwallet5` runs in `auth`, `plasma-kwallet-pam.service` starts, and the Secret Service `Locked` property is `false` on a wallet created earlier with the user's password.
- `claire.preinstall` installs its five Flatpaks on the first boot after the switch (`flatpak-preinstall.service`), on top of the Flatpaks the ISO installs.
- `bootc switch` to the local registry image works; the upstream deployment stays as rollback.

- GRUB comes from bootupd's static config, written to `/boot/grub2/grub.cfg` at install (not updated by image upgrades): `timeout_style=menu`, `timeout=1`, then it sources `$prefix/custom.cfg` last. `/boot` is outside the image and mounted rw, so `aurora-config-grub.service` copies `usr/lib/aurora-config/grub-custom.cfg` and the Breeze theme there at every boot (effect at the next boot; files get `boot_t`). The theme (`grub2-breeze-theme`, which installs into `/boot`) is extracted at build with `rpm2cpio` into `/usr/lib/aurora-config/grub-themes/`. It renders under Secure Boot. Its Unifont fonts are ASCII-only: the user chose not to translate the theme. Entry titles (`Aurora (Version: …) (ostree:N)`) come from ostree and stay as is.

- uupd (1.4): `uupd.timer` daily at 04:00 local + up to 15 min random, `Persistent=true`; `uupd.service` runs `uupd --log-level=debug --json`, `Restart=on-failure` (60 s, 3 tries / 10 min). Hardware checks enabled by default config (logic in `checks/hardware.go` of ublue-os/uupd): on battery only, ≥ 20 % and power profile not `power-saver`; CPU < 50 %, memory < 90 %; network fully connected, not metered (NM `Metered` yes/guess-yes blocks), < 700 kB/s averaged over 5 s. Modules: system (bootc), flatpak, brew; distrobox disabled by Aurora's `/etc/uupd/config.json`. It never reboots (no `--apply`). Inspect with `uupd config-dump`.
- `ujust` recipes live in `/usr/share/ublue-os/just/*.just` (read them there before recommending one). `rebase-helper` and `toggle-devmode` rebase to another Aurora image, leaving `aurora-claire`; `toggle-tailscale` cuts remote access; `toggle-tpm2` contradicts a decision below. `check-local-overrides` diffs `/etc` against `/usr/etc` (drift check).

## Decisions (do not revisit without the user)

- **Secure Boot on, no hibernation.** Fedora kernels enter lockdown under Secure Boot, which disables hibernation. Suspend only.
- **LUKS passphrase, no TPM unlock.** With autologin, TPM-only would hand the session to whoever powers the laptop on.
- **Autologin + wallet unlocked by the LUKS passphrase** (`pam_systemd_loadkey` + `KeyringMode=inherit`, the `arch-config` method). Requires Claire's user password to equal the LUKS passphrase.
- **Claire is an admin (`wheel`)**, so Bazaar, fwupd and printers never ask for someone else's password. **Gabriel has his own admin account `gaugendre`**, created manually after install (`useradd -m -G wheel`), used over Tailscale SSH with his own password; Claire's password (= LUKS passphrase) stays hers. Not created by the image on purpose.
- **No settings backup.** Files sync to pCloud; Firefox Sync; Steam Cloud.
- Settings from `arch-config` deliberately **not** carried over: KVM USB wakeup (his desk), Limine font, pstore/panic-on-hang debugging, hibernation hooks, ufw/Docker/exit-node config.

## Not yet verified (check in the VM, then on the laptop)

- On real hardware: PSR karg, ACP blacklist, suspend, fingerprint, `steam-devices` with a controller.

Move each item to the facts or rules above once checked, with the date.

## VM bench

VM `aurora-test`, files in `/var/lib/libvirt/images/aurora-test/`, created with the `virt-install` command in `README.md`. Arch's OVMF ships no pre-enrolled keys (Secure Boot would not be enforced), so the README builds `OVMF_VARS.ms.4m.fd` with `virt-fw-vars --enroll-redhat --secure-boot` and passes it as `nvram.template`; `firmware.feature…enrolled-keys=yes` fails on Arch. The `default` NAT network exists but is not autostarted: `virsh net-start default`. The user installs through the virt-manager console; MOK enrollment password is `universalblue`. `arch-config/vm/README.md` documents `virsh send-key` and screenshot tricks that apply here too (keys are physical QWERTY positions).

The VM follows the locally built image through a `registry:2` container on the host (`aurora-registry`, published on `127.0.0.1:5000` and `192.168.122.1:5000`; Docker only pushes over HTTP to `localhost`). The VM marks `192.168.122.1:5000` insecure in `/etc/containers/registries.conf.d/50-banc-de-test.conf`. Iterate with `docker build -f Containerfile -t localhost:5000/aurora-claire . && docker push localhost:5000/aurora-claire`, then `sudo bootc upgrade && systemctl reboot` in the VM.
