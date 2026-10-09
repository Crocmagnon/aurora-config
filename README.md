# aurora-config

Image [bootc](https://github.com/bootc-dev/bootc) du Framework 13 AMD (Ryzen AI 300) de Claire : [Aurora](https://getaurora.dev) (Fedora Atomic, KDE Plasma) plus quelques réglages. Construit depuis [ublue-os/image-template](https://github.com/ublue-os/image-template).

GitHub Actions reconstruit l'image chaque nuit et à chaque push sur `main`, par-dessus la dernière `aurora:stable`, puis la publie signée sur `ghcr.io/crocmagnon/aurora-claire`. Le laptop la télécharge tout seul (uupd) et l'applique au redémarrage suivant. L'image précédente reste dans le menu de démarrage. Un build qui échoue ne publie rien : le laptop garde la dernière image.

Les dépôts voisins : `arch-config` (mes machines Arch, decman) et `nixos-config` (srv-1).

## Ce que l'image ajoute à Aurora

- **Autologin** de `claire` (`/etc/plasmalogin.conf.d/autologin.conf`), avec le **wallet KDE ouvert par la passphrase LUKS** : `pam_systemd_loadkey` inséré dans le fichier PAM d'autologin (`build.sh`), `KeyringMode=inherit` sur `plasmalogin.service`. Il faut donc que le mot de passe de `claire` soit la passphrase LUKS. Une seule saisie au démarrage, puis la même pour l'écran de verrouillage.
- **AZERTY à l'invite LUKS** : `vconsole.keymap=fr` (l'initramfs d'Aurora est générique).
- **Framework 13 AMD** (repris de `arch-config`) : `amdgpu.dcdebugmask=0x10`, blacklist de l'audio ACP fantôme.
- **Paquets** : `steam-devices` (manettes), `fuse-libs` (AppImage pCloud), `hunspell-fr`.
- **Flatpaks préinstallés** (`claire.preinstall`) : Firefox, Steam, OnlyOffice, Gear Lever, KTailctl.

Pas d'hibernation : avec Secure Boot, le noyau Fedora passe en lockdown, qui l'interdit. Veille simple ; à batterie critique, Plasma éteint proprement.

## Installer

1. ISO : <https://dl.getaurora.dev/aurora-stable-webui-x86_64.iso>. Secure Boot reste activé.
2. Installation : langue française, clavier `fr`, partitionnement automatique, **chiffrement coché**. Compte `claire` (nom affiché « Claire »), administrateur, avec la passphrase LUKS comme mot de passe.
3. Au premier démarrage, écran bleu MOK : « Enroll MOK », mot de passe `universalblue`.
4. Basculer sur cette image, puis redémarrer :
   ```sh
   sudo bootc switch ghcr.io/crocmagnon/aurora-claire:latest
   ```

## Après l'installation

- `sudo tailscale up --ssh --operator=claire`, puis dans la console Tailscale : **désactiver l'expiration de la clé** de la machine (sinon l'accès de dépannage disparaît au bout de 180 jours).
- pCloud : télécharger l'AppImage, l'ouvrir avec Gear Lever, se connecter, activer le démarrage avec la session, et synchroniser `~/Documents`, `~/Images` et `~/Bureau`.
- Connexions : Steam, Firefox Sync.
- `fwupdmgr refresh && fwupdmgr update`.
- Contrôles :
  - `rpm-ostree status` : l'image démarrée est `ghcr.io/crocmagnon/aurora-claire`.
  - Wallet ouvert à l'autologin : `busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/kdewallet org.freedesktop.Secret.Collection Locked` répond `b false`.

## Corriger un problème

1. **Sur la machine, via Tailscale SSH**, essayer le correctif :
   - fichier dans `/usr` : `sudo bootc usr-overlay` (modifiable jusqu'au redémarrage) ;
   - paquet : `sudo rpm-ostree install --apply-live <paquet>` ;
   - configuration : directement dans `/etc` ;
   - paramètre noyau : `sudo rpm-ostree kargs --append=<karg>`.
2. **Reporter le correctif ici** : de préférence dans `system_files/usr/lib/...` (sysctl.d, modprobe.d, systemd, udev, `bootc/kargs.d`), qui fait autorité ; un fichier de `/etc` modifié localement masquerait l'image pour toujours. Les paquets vont dans `build_files/build.sh`.
3. **Retirer la bidouille locale** une fois l'image publiée et appliquée : `sudo rpm-ostree reset`, `sudo rpm-ostree kargs --delete=<karg>`, annuler les modifications de `/etc`.
4. **Vérifier l'absence de dérive** : `rpm-ostree status` (aucun paquet ajouté localement) et `sudo ostree admin config-diff` (fichiers de `/etc` qui diffèrent de l'image).

En cas de casse : `sudo bootc rollback` puis redémarrer, ou choisir l'entrée précédente dans le menu de démarrage.

## Ajouter une image

Le nom de l'image (`IMAGE_NAME` dans `image-template.env`) est distinct de celui du repo pour qu'une autre image puisse s'y ajouter : il faudra alors un Containerfile par image et une matrice dans `.github/workflows/build.yml`.
