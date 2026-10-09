# CLAUDE.md

Guidance for Claude Code in this repository. Keep it and `README.md` current: update both whenever a file, a decision or a procedure changes, not at the end. `README.md` is for humans, in French; this file is for agents.

## What this is

A bootc image for Claire's Framework 13 AMD (Ryzen AI 300): `FROM ghcr.io/ublue-os/aurora:stable` (Fedora Atomic, KDE Plasma) plus a few settings. Claire is not technical: she only uses the desktop and the Bazaar store. The user (Gabriel) administers the machine remotely over Tailscale SSH.

Sibling repos, same owner:
- `~/Projects/codeberg.org/Crocmagnon/arch-config`: his Arch machines (decman). Framework-specific settings come from there; read its `CLAUDE.md` and `decman/framework_gab_amd.py` before adding hardware tweaks.
- `nixos-config`: srv-1. Never touch it.

## How it ships

- `.github/workflows/build.yml` builds on every push to `main`, nightly (10:05 UTC) and on pull requests. PRs build but never publish.
- On `main`, it pushes `ghcr.io/crocmagnon/aurora-claire:latest` and signs it with cosign (secret `SIGNING_SECRET`; public key `cosign.pub`).
- The laptop runs `bootc switch`ed to that image. uupd stages updates; they apply at next reboot.
- **A push to `main` is a deployment to Claire's laptop.** Prefer a branch + PR, and never push to `main` without the user's go.

## Layout

| Path | Role |
|---|---|
| `Containerfile` | `FROM aurora:stable` (no digest, on purpose), runs `build.sh`, then `bootc container lint` |
| `build_files/build.sh` | Copies `system_files/` to `/` (owned by root), installs packages, patches the PAM autologin file |
| `system_files/` | Copied as-is to the image root |
| `image-template.env` | `IMAGE_NAME=aurora-claire` (differs from the repo name so more images can be added) |
| `Justfile` | Template's build recipes, used by CI. Left as upstream to ease template merges |
| `disk_config/` | Unused (ISO builds were removed); kept because `Justfile` references it |

## Rules

- **Put config under `/usr/lib` (or `/usr/share`) rather than `/etc`.** `/etc` gets a three-way merge: a locally modified file masks the image forever. Use `system_files/etc/` only when the software reads nothing under `/usr` (none today).
- **Kernel args go in `system_files/usr/lib/bootc/kargs.d/*.toml`**, one file per topic. bootc applies them on switch and upgrade.
- **Patch package-owned files in `build.sh` instead of copying them**, and make the build fail if the anchor disappears (see the PAM `sed` + `grep`). A copied file would silently drift from Fedora's.
- **Cite the origin** in a comment when a setting comes from `arch-config` or nixos-hardware.
- **Changing dracut config requires regenerating the initramfs in `build.sh`.** Aurora builds it in `build_scripts/base/19-initramfs.sh` (ublue-os/aurora): copy that command, including its os-release handling.
- **Secrets never go in the image or the repo in clear.** If one must be versioned, use git-crypt. The cosign private key exists only as the GitHub secret; regenerate rather than store it.
- **Build locally before pushing**, with the procedure in `README.md` (« Construire en local »): the host has Docker without buildx and no podman, so `docker build` fails on `RUN --mount`; instead run `build.sh` in an `aurora:stable` container with the build context bind-mounted at `/ctx`, then `docker commit` and `bootc container lint`. The 3 lint warnings about dnf caches are local-only. CI stays the source of truth (`gh run watch`, `gh run view --log-failed`).
- **Never let `system_files/` ownership leak into the image.** `build.sh` copies with `--no-preserve=ownership`: a plain `cp -a` from a bind mount makes `/etc`, `/usr` and our files owned by uid 1000, which is Claire on the laptop. In CI, `COPY` already gives root, but do not rely on it. Check with `find / -xdev -uid 1000` in the built image.
- **Inspect upstream Aurora** with `docker run --rm ghcr.io/ublue-os/aurora:stable …` (pulled locally) or its sources (`gh repo clone ublue-os/aurora`).
- **Comments, docs and commit messages are in French**, like the sibling repos.

## Facts about upstream Aurora (verified in its sources, October 2026)

- Display manager is **plasma-login-manager** (`plasmalogin.service`), same as `arch-config`.
- Preset-enabled: `tailscaled.service`, `uupd.timer`, `flatpak-preinstall.service`. Flatpak's `preinstall.d` is supported; Aurora itself ships `bazaar.preinstall`.
- Removed on purpose: `plasma-discover`, the `firefox` RPM, `fedora-flathub-remote`. The store is Bazaar; Firefox is a Flatpak.
- The initramfs is generic, built at image build time: it does not read the machine's `/etc/vconsole.conf`, hence `vconsole.keymap=fr` in `kargs.d`.
- ublue LUKS dracut config adds `fido2 pkcs11 pcsc`.
- PAM files live in `/usr/lib/pam.d/` (no copy in `/etc/pam.d/`). Fedora's `plasmalogin-autologin` calls `pam_kwallet5` only in the `session` phase; `plasmalogin` (password login) also calls it in `auth`. `build.sh` therefore inserts `pam_systemd_loadkey` then `-auth pam_kwallet5` before `auth include postlogin`. `pam_systemd_loadkey.so` and `pam_kwallet5.so` (package `pam-kwallet`) are both present.
- plasma-login-manager reads `/usr/lib/plasmalogin/plasmalogin.conf.d/` (shipped empty by the package) and `/etc/plasmalogin.conf.d/`; `/etc/plasmalogin.conf` is all comments. Autologin session file is `/usr/share/wayland-sessions/plasma.desktop` (`Session=plasma`).
- `fuse-libs` is already in Aurora; `steam-devices` and `hunspell-fr` come from Fedora repos. Kept explicit in `build.sh` to document why they matter.

## Decisions (do not revisit without the user)

- **Secure Boot on, no hibernation.** Fedora kernels enter lockdown under Secure Boot, which disables hibernation. Suspend only.
- **LUKS passphrase, no TPM unlock.** With autologin, TPM-only would hand the session to whoever powers the laptop on.
- **Autologin + wallet unlocked by the LUKS passphrase** (`pam_systemd_loadkey` + `KeyringMode=inherit`, the `arch-config` method). Requires Claire's user password to equal the LUKS passphrase.
- **No settings backup.** Files sync to pCloud; Firefox Sync; Steam Cloud.
- Settings from `arch-config` deliberately **not** carried over: KVM USB wakeup (his desk), Limine font, pstore/panic-on-hang debugging, hibernation hooks, ufw/Docker/exit-node config.

## Not yet verified (check in the VM, then on the laptop)

- That plasmalogin honours autologin from `/usr/lib/plasmalogin/plasmalogin.conf.d/` (inferred from the package's empty dir, by analogy with SDDM's system config dir). If not, move it back to `system_files/etc/plasmalogin.conf.d/`.
- That SELinux lets `plasmalogin` read the `cryptsetup` key from the kernel keyring (Arch has no SELinux). Check `sudo ausearch -m avc -ts boot` if the wallet stays locked.
- That the wallet actually unlocks at autologin with Fedora's dracut initramfs (proven only with mkinitcpio on Arch). Check: `busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/kdewallet org.freedesktop.Secret.Collection Locked` → `b false`.
- That `vconsole.keymap=fr` gives AZERTY at the LUKS prompt (generic dracut should include all keymaps). Test with a passphrase containing a, q, z, w, m.
- Whether the Aurora ISO's installer and first LUKS prompt are QWERTY-only (reported by Aurora testers).
- That `claire.preinstall` installs the five Flatpaks on first boot after the switch.

Move each item to the facts or rules above once checked, with the date.

## VM bench

VM `aurora-test`, files in `/var/lib/libvirt/images/aurora-test/`, created with the `virt-install` command in `README.md`. Arch's OVMF ships no pre-enrolled keys (Secure Boot would not be enforced), so the README builds `OVMF_VARS.ms.4m.fd` with `virt-fw-vars --enroll-redhat --secure-boot` and passes it as `nvram.template`; `firmware.feature…enrolled-keys=yes` fails on Arch. The `default` NAT network exists but is not autostarted: `virsh net-start default`. The user installs through the virt-manager console; MOK enrollment password is `universalblue`. `arch-config/vm/README.md` documents `virsh send-key` and screenshot tricks that apply here too (keys are physical QWERTY positions).
