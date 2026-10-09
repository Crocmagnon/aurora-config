# aurora-config

Système du Framework 13 AMD (Ryzen AI 300) de Claire, décrit dans ce dépôt sous forme d'**image bootc** : [Aurora](https://getaurora.dev) (Fedora Atomic avec KDE Plasma) plus quelques réglages. Le dépôt part de [ublue-os/image-template](https://github.com/ublue-os/image-template).

Les dépôts voisins :
- [`arch-config`](https://codeberg.org/Crocmagnon/arch-config) : mes machines Arch (decman). Les réglages propres au Framework 13 AMD en viennent ;
- `nixos-config` : srv-1.

## Sommaire

1. [Le principe](#le-principe)
2. [Ce que l'image ajoute à Aurora](#ce-que-limage-ajoute-à-aurora)
3. [Les choix faits](#les-choix-faits)
4. [Au quotidien](#au-quotidien)
5. [Installer la machine](#installer-la-machine)
6. [Modifier l'image](#modifier-limage)
7. [Corriger un problème sur la machine](#corriger-un-problème-sur-la-machine)
8. [Revenir en arrière](#revenir-en-arrière)
9. [Tester dans une VM](#tester-dans-une-vm)
10. [ujust](#ujust)
11. [Aide-mémoire](#aide-mémoire)

## Le principe

### Un système en image

Sur Aurora, l'OS est une image de conteneur (OCI), démarrée telle quelle. Le disque est découpé en zones aux règles différentes :

| Zone | Contenu | Écriture | À la mise à jour |
|---|---|---|---|
| `/usr` | L'OS : programmes, bibliothèques, KDE, unités systemd, udev, polkit… | lecture seule | remplacé en bloc par la nouvelle image |
| `/etc` | Configuration de la machine | oui | fusion en trois voies : un fichier modifié localement est gardé tel quel, les autres suivent l'image |
| `/var`, `/home` | Données, Flatpaks, Homebrew, conteneurs | oui | jamais touché |

Un **déploiement**, c'est une image plus son `/etc`. Une mise à jour ne modifie jamais le système qui tourne : elle prépare un nouveau déploiement à côté, qui devient actif au redémarrage. Le précédent reste dans le menu de démarrage.

### Le chemin d'une mise à jour

```
ghcr.io/ublue-os/aurora:stable      reconstruite régulièrement par Universal Blue
        │
        ▼
ce dépôt, GitHub Actions             FROM aurora:stable + nos réglages
  (chaque nuit à 0h05 UTC,           → build, signature cosign
   et à chaque push sur main)
        │
        ▼
ghcr.io/crocmagnon/aurora-claire:latest
        │
        ▼
le laptop, uupd.timer               chaque jour à 4h (heure locale), ou au réveil
                                    → bootc upgrade (prépare le déploiement),
                                      flatpak update, brew upgrade
        │
        ▼
redémarrage suivant                 nouvelle image, l'ancienne reste disponible
```

- Le laptop suit **notre** image, pas celle d'Universal Blue. Il reçoit leurs mises à jour au plus tard le lendemain, via notre build de la nuit.
- **Un build qui échoue ne publie rien** : le laptop garde la dernière image. GitHub envoie un e-mail.
- Une pull request construit l'image sans la publier : c'est la façon de tester une modification sans l'envoyer au laptop.
- Les Flatpaks se mettent à jour à part, sans redémarrage.
- Si Claire ne redémarre jamais, la mise à jour attend. Elle s'applique au prochain redémarrage.

### Les mises à jour automatiques sur le laptop (uupd)

[uupd](https://github.com/ublue-os/uupd) est l'outil de mise à jour d'Universal Blue, fourni et activé par Aurora. Rien n'est réglé dans ce dépôt.

**Quand.** `uupd.timer` (`/usr/lib/systemd/system/uupd.timer`) lance `uupd.service` :
- chaque jour à **4h00, heure locale**, avec un délai aléatoire de 0 à 15 min ;
- `Persistent=true` : si le laptop était éteint ou en veille à 4h, la mise à jour part **dès le démarrage ou le réveil suivant**. En pratique, c'est le cas le plus courant.

**À quelles conditions.** Avant de commencer, uupd vérifie que la machine est disponible (seuils : `uupd config-dump`, section `checks.hardware` ; logique : `checks/hardware.go` dans le code de uupd) :
- sur batterie : au moins 20 %, et pas en mode « économie d'énergie » (sur secteur, pas de condition) ;
- processeur occupé à moins de 50 %, mémoire à moins de 90 % ;
- réseau connecté, **pas marqué comme limité** (partage de connexion du téléphone, par exemple), et peu utilisé (moins de 700 Ko/s en moyenne sur 5 s) : pas de mise à jour en pleine visio.

Si une condition manque, il n'installe rien cette fois-là. Si le service échoue (Wi-Fi pas encore connecté au réveil, par exemple), systemd le relance au bout d'une minute, trois fois au plus en 10 minutes ; sinon, ce sera au prochain déclenchement.

**Ce qu'il met à jour**, dans l'ordre :
1. **le système** : `bootc upgrade` télécharge notre image si elle a changé et prépare le nouveau déploiement. Rien ne change avant le redémarrage suivant, et uupd ne redémarre jamais tout seul ;
2. **les Flatpaks** (système et utilisateur), appliqués tout de suite ; une application ouverte passe à la nouvelle version à sa prochaine ouverture ;
3. **Homebrew**, s'il est utilisé.

Distrobox est exclu par Aurora (`/etc/uupd/config.json`).

**Suivre et intervenir :**
- `systemctl list-timers uupd.timer` : prochaine et dernière exécution ;
- `journalctl -u uupd.service` : ce qu'il a fait (JSON) ;
- `rpm-ostree status` : un déploiement préparé apparaît au-dessus de l'actuel ;
- `ujust update` : tout mettre à jour tout de suite ;
- `ujust toggle-updates` : vérifier qu'elles sont actives (elles doivent le rester) ;
- `sudo uupd update-check` : y a-t-il une image plus récente ?

### Où s'installent les applications

| Moyen | Pour quoi | Qui |
|---|---|---|
| **Flatpak** (Flathub), depuis la boutique **Bazaar** | toutes les applications de bureau | Claire, seule |
| **AppImage** via Gear Lever | ce qui n'existe qu'en AppImage (pCloud) | une fois, à l'installation |
| **Homebrew** | outils en ligne de commande | moi, pour dépanner |
| **Distrobox** | un conteneur d'une autre distribution intégré au bureau | moi, au besoin |
| **cette image** (`build.sh`) | ce qui doit faire partie de l'OS : pilotes, règles udev, démons | moi, par commit |

Aurora n'a ni Discover ni le Firefox en RPM : la boutique est Bazaar, Firefox est un Flatpak.

## Ce que l'image ajoute à Aurora

| Réglage | Fichier | Pourquoi |
|---|---|---|
| Autologin de `claire` | `system_files/usr/lib/plasmalogin/plasmalogin.conf.d/autologin.conf` | une seule saisie au démarrage : la passphrase LUKS |
| Wallet KDE ouvert par la passphrase LUKS | `build_files/build.sh` (PAM), `system_files/usr/lib/systemd/system/plasmalogin.service.d/keyring.conf` | sans ça, l'autologin laisse le wallet fermé et chaque application (Wi-Fi, pCloud…) le redemande |
| PSR désactivé (`amdgpu.dcdebugmask=0x10`) | `system_files/usr/lib/bootc/kargs.d/10-framework.toml` | repris de `arch-config` (nixos-hardware) |
| Blacklist de l'audio ACP | `system_files/usr/lib/modprobe.d/framework-acp.conf` | le BIOS déclare à tort ce périphérique : interface audio fantôme (repris de `arch-config`) |
| `steam-devices` | `build.sh` | règles udev des manettes, que le Flatpak Steam ne peut pas poser |
| `fuse-libs` | `build.sh` | FUSE 2, nécessaire à l'AppImage pCloud |
| `hunspell-fr` | `build.sh` | correcteur orthographique des applications KDE |
| Menu de démarrage visible 5 s, avec le thème Breeze de KDE | `system_files/usr/lib/aurora-config/grub-custom.cfg`, `system_files/usr/lib/systemd/system/aurora-config-grub.service`, `build.sh` (thème) | par défaut, le menu GRUB ne reste qu'une seconde, en texte brut. `/boot` ne fait pas partie de l'image : le service y recopie le réglage et le thème à chaque démarrage, effet au démarrage suivant |
| Flatpaks préinstallés : Firefox, Steam, OnlyOffice, Gear Lever, KTailctl | `system_files/usr/share/flatpak/preinstall.d/claire.preinstall` | installés au démarrage par `flatpak-preinstall.service` ; une application que Claire désinstalle n'est pas réinstallée |

Déjà fournis par Aurora, sans rien à faire ici : Tailscale (`tailscaled` activé), uupd, plasma-login-manager, power-profiles, fwupd, codecs.

### Le wallet ouvert par la passphrase LUKS

Même méthode que dans `arch-config` (Arch Wiki, *KDE Wallet*) :
1. au démarrage, systemd-cryptsetup déverrouille le disque et laisse la passphrase dans le trousseau du noyau ;
2. `plasmalogin.service` en hérite grâce à `KeyringMode=inherit` ;
3. dans le fichier PAM d'autologin, `pam_systemd_loadkey` la lit, puis `pam_kwallet5` (phase `auth`) la récupère et ouvre le wallet en phase `session`.

Condition : **le mot de passe de `claire` est la passphrase LUKS**. C'est aussi plus simple pour elle : un seul secret, saisi au démarrage et à l'écran de verrouillage.

Le fichier d'autologin de Fedora (`/usr/lib/pam.d/plasmalogin-autologin`) n'appelle `pam_kwallet5` qu'en phase `session`, alors que celui de la connexion par mot de passe l'appelle aussi en phase `auth`. `build.sh` ajoute donc les deux lignes `auth` avant `auth include postlogin`, au lieu de remplacer le fichier : les mises à jour de Fedora continuent de s'appliquer, et le build échoue si la ligne d'ancrage disparaît.

## Les choix faits

- **Aurora plutôt qu'Ubuntu, Kinoite ou NixOS.** Image immuable, mises à jour atomiques, retour arrière natif, Flatpak pour Claire, et tout le système décrit dans un dépôt : pas de dérive possible sur `/usr`. Ubuntu + Ansible ne garantit que ce qui est déclaré. Kinoite demanderait de refaire ce qu'Aurora fournit. NixOS coûte plus cher à entretenir.
- **Aurora plutôt que Bazzite.** Bazzite vise le jeu. Pour du jeu occasionnel, le Flatpak Steam suffit. Si ça change, il suffit de changer le `FROM`.
- **Secure Boot activé, pas d'hibernation.** Avec Secure Boot, le noyau Fedora passe en lockdown, qui interdit l'hibernation. Veille simple : à batterie critique, Plasma éteint proprement. L'hibernation de mon laptop sous Arch avait en plus un blocage pas encore compris (voir `panic-on-hang` dans `arch-config`).
- **Claire administratrice, plus un compte administrateur pour moi.** Sans droits d'administration, chaque installation depuis Bazaar, mise à jour de firmware ou imprimante demanderait mon mot de passe. Le risque est faible : `/usr` est en lecture seule et le rollback rattrape une erreur système. Mon compte `gaugendre` (créé à la main, une fois) me sert à dépanner avec mon propre mot de passe : celui de Claire reste à elle.
- **Passphrase LUKS, pas de déverrouillage par TPM.** Avec l'autologin, un TPM seul ouvrirait la session de Claire à qui allume le laptop.
- **Image non figée** (`FROM aurora:stable` sans digest). Le build de chaque nuit reprend ainsi la dernière Aurora. C'est pour ça que Renovate est retiré du template : il aurait figé la base.
- **Dépôt public.** Le laptop télécharge l'image sans identifiants, et rien dans l'image n'est secret.
- **Pas de sauvegarde des réglages.** Fichiers dans pCloud (dossiers synchronisés), navigateur par Firefox Sync, jeux par Steam Cloud. Les réglages KDE se refont en un quart d'heure.
- **Renovate pour les actions GitHub seulement** (comme dans mes autres dépôts, une fois par mois). Il ne touche pas au Containerfile : il figerait la base sur un digest.
- **Nom d'image distinct du nom du dépôt** (`aurora-claire`), pour accueillir d'autres images plus tard (voir [Ajouter une image](#ajouter-une-image)).

## Au quotidien

**Claire** utilise KDE. Elle installe ses applications depuis Bazaar, et tout se met à jour sans rien lui demander. Les mises à jour de l'OS s'appliquent quand elle éteint ou redémarre. La seule chose à lui apprendre : si un jour le laptop démarre mal, choisir la deuxième ligne du menu de démarrage (il reste affiché 5 secondes) et m'appeler. Les deux lignes s'appellent « Aurora (Version: …) (ostree:0) » et « (ostree:1) » : ostree génère ces titres, on ne peut pas les renommer proprement.

**Moi** :
- un e-mail de GitHub si le build de la nuit échoue (la cause est presque toujours en amont : relancer le lendemain ou corriger `build.sh`) ;
- de temps en temps, `rpm-ostree status` via Tailscale SSH, pour vérifier qu'elle a redémarré récemment et qu'aucune bidouille locale ne traîne ;
- les dépannages, avec la méthode décrite plus bas.

## Installer la machine

À faire d'abord dans une VM (voir [Tester dans une VM](#tester-dans-une-vm)), puis sur le laptop.

### 1. Installation d'Aurora

1. ISO : <https://dl.getaurora.dev/aurora-stable-webui-x86_64.iso>, avec son `-CHECKSUM` (`sha256sum -c`). Sur une clé USB (pas Ventoy, que les ISO Aurora ne supportent pas).
2. BIOS du Framework : Secure Boot reste activé.
3. Dans l'installeur :
   - langue : français ; clavier : `fr (oss)`, proposé par défaut (mêmes lettres et chiffres que `fr`) ;
   - partitionnement automatique (`/boot/efi`, `/boot` en clair, puis une partition LUKS en btrfs avec `/`, `/home` et `/var`), **chiffrement coché** ;
   - passphrase : lettres, chiffres et symboles courants, sans AltGr (les variantes d'AZERTY ne diffèrent que là). Vérifier avec l'icône en forme d'œil qu'elle s'affiche comme prévu.

   L'installation se fait depuis l'image embarquée dans l'ISO, sans réseau. L'indicateur reste immobile pendant l'écriture (une dizaine de Go) : c'est normal.
4. Premier démarrage, écran bleu MOK : « Enroll MOK », mot de passe `universalblue`. Cela enregistre la clé Secure Boot d'Universal Blue. **Cet écran est toujours en QWERTY** : sur un clavier AZERTY, taper `universqlblue`.
   L'invite LUKS, elle, suit déjà le clavier choisi dans l'installeur.
5. Assistant de premier démarrage : compte `claire`, nom affiché « Claire », administrateur, avec **la passphrase LUKS comme mot de passe**. L'installeur ne crée aucun compte.

### 2. Passage sur cette image

```sh
sudo bootc switch ghcr.io/crocmagnon/aurora-claire:latest
systemctl reboot
```

Au redémarrage : `rpm-ostree status` doit montrer `ghcr.io/crocmagnon/aurora-claire:latest` comme image démarrée.

### 3. Réglages manuels, une seule fois

Ces réglages vivent dans `/var` ou dans le dossier de Claire : ils survivent aux mises à jour, mais ne peuvent pas venir de l'image.

- **Mon compte administrateur**, pour dépanner sans connaître le mot de passe de Claire (qui est aussi sa passphrase LUKS) :
  ```sh
  sudo useradd -m -G wheel gaugendre && sudo passwd gaugendre
  ```
  Il n'apparaît pas au démarrage (autologin), seulement dans « Changer d'utilisateur ».
- **Tailscale**, pour que je puisse dépanner. Mêmes options que sur mes machines (`arch-config`), connecté avec **mon** compte Tailscale :
  ```sh
  sudo tailscale up --operator=claire --ssh --accept-routes --accept-dns
  ```
  - `--operator=claire` : Claire pilote Tailscale sans `sudo`, ce qu'il faut à KTailctl. Un seul opérateur possible : moi, j'utilise `sudo tailscale …` depuis mon compte administrateur ;
  - `--ssh` : tailscaled sert lui-même SSH, sans serveur SSH sur la machine. Les règles `ssh` du tailnet doivent autoriser l'utilisateur `gaugendre` sur cette machine (la règle par défaut, `autogroup:self` vers `autogroup:nonroot`, le permet si la machine est enregistrée sur mon compte) ;
  - `--accept-routes`, `--accept-dns` : routes et DNS du tailnet, comme sur mes machines.

  Puis, dans la console d'administration Tailscale, **désactiver l'expiration de la clé** de cette machine. Sinon, l'accès disparaît au bout de 180 jours.
- **KTailctl au démarrage**, dans la session de Claire : Configuration du système → Démarrage automatique → Ajouter… → Ajouter une application → KTailctl. Puis, dans KTailctl → Paramètres, cocher « Démarrer réduit » : il se lance dans la zone de notification, sans fenêtre. KTailctl n'a pas d'option de lancement au démarrage, et le Flatpak ne lit pas de config dans `/etc/xdg` : d'où ce réglage manuel plutôt que dans l'image.
- **pCloud** : télécharger l'AppImage sur pcloud.com, l'ouvrir avec Gear Lever, se connecter, activer le démarrage avec la session. Puis synchroniser `~/Documents`, `~/Images` et `~/Bureau` : ses fichiers sont sauvegardés sans qu'elle ait à y penser. pCloud se met à jour lui-même, pas par uupd.
- **Comptes** : Steam, Firefox Sync.
- **Empreinte digitale** (si elle veut) : Configuration du système, Utilisateurs.
- **Firmware** : `fwupdmgr refresh && fwupdmgr update`.

### 4. Contrôles

- `rpm-ostree status` : image `aurora-claire`, aucun paquet ajouté localement.
- `rpm-ostree kargs` contient `amdgpu.dcdebugmask=0x10`, et `vconsole.keymap=fr-oss` (posé par l'installeur).
- Redémarrer : une passphrase en AZERTY, puis le bureau sans autre saisie.
- Wallet ouvert à l'autologin : la commande suivante répond `b false` :
  ```sh
  busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/kdewallet org.freedesktop.Secret.Collection Locked
  ```
- `flatpak list --app` : Firefox, Steam, OnlyOffice, Gear Lever, KTailctl.

## Modifier l'image

```
Containerfile                   FROM aurora:stable, puis build.sh
build_files/build.sh            paquets et modifications par script
system_files/                   copié tel quel à la racine de l'image
  usr/lib/bootc/kargs.d/        paramètres du noyau (un .toml par sujet)
  usr/lib/modprobe.d/           modules du noyau
  usr/lib/systemd/system/       unités et drop-ins systemd
  usr/lib/plasmalogin/plasmalogin.conf.d/   configuration de l'écran de connexion
  usr/share/flatpak/preinstall.d/   Flatpaks préinstallés
  etc/                          seulement si le logiciel ne lit rien sous /usr
image-template.env              nom et description de l'image
.github/workflows/build.yml     build, publication, signature
cosign.pub                      clé publique de signature
```

Règles :
- **Préférer `/usr/lib` à `/etc`.** `/usr/lib/sysctl.d`, `/usr/lib/udev/rules.d`, `/usr/lib/systemd/...`, `/usr/lib/tmpfiles.d`, `/usr/share/polkit-1/rules.d` font autorité : l'image gagne toujours. Un fichier de `/etc` modifié sur la machine masquerait l'image pour toujours.
- **Un paramètre du noyau = un fichier dans `kargs.d`**, appliqué au `bootc switch` et à chaque mise à jour.
- **Un réglage repris d'`arch-config` cite son origine** en commentaire.
- **Passer par une pull request** : le build est testé sans être publié. Le merge sur `main` publie l'image, que le laptop applique au redémarrage suivant.
- Une modification de la configuration dracut doit reconstruire l'initramfs dans `build.sh`, comme le fait Aurora (`build_scripts/base/19-initramfs.sh` dans [ublue-os/aurora](https://github.com/ublue-os/aurora)).

Suivre un build : `gh run watch`. Le relancer sans commit : `gh workflow run build.yml`.

### Construire en local

Plus rapide que GitHub pour mettre au point `build.sh` : une erreur apparaît en une minute. Il faut Docker avec buildx (paquet `docker-buildx`), car le Containerfile utilise `RUN --mount`.

```fish
docker build -f Containerfile -t localhost/aurora-claire .
```

Le `bootc container lint` du Containerfile tourne aussi. Le premier build télécharge l'image Aurora (plusieurs Go) ; les suivants la réutilisent. Pour repartir de la dernière Aurora : `docker pull ghcr.io/ublue-os/aurora:stable` avant le build.

Pour inspecter l'image : `docker run --rm -it localhost/aurora-claire bash`.

### Ajouter une image

Pour une deuxième machine : un Containerfile par image (ex. `Containerfile.gab`) et une matrice dans `.github/workflows/build.yml`. Le `Justfile` lit le nom de l'image dans `image-template.env` : le passer en paramètre. Les réglages communs peuvent aller dans un `build_files/common.sh` appelé par chaque image.

### Signature

GitHub Actions signe chaque image avec cosign. La clé privée n'existe que dans le secret `SIGNING_SECRET` du dépôt. Pour la changer : `COSIGN_PASSWORD="" cosign generate-key-pair`, `gh secret set SIGNING_SECRET < cosign.key`, remplacer `cosign.pub`, effacer `cosign.key`. Un secret à versionner passerait par git-crypt.

Le laptop ne vérifie pas encore la signature (il faudrait une politique dans `/etc/containers/policy.json`).

## Corriger un problème sur la machine

On ne sait pas toujours quel est le bon correctif avant de l'avoir essayé. D'où trois temps : bidouiller sur place, reporter dans l'image, nettoyer.

### 1. Essayer sur place

Via Tailscale SSH, avec mon compte (`ssh gaugendre@<nom-tailscale>`), `sudo` avec mon mot de passe :

| À essayer | Commande | Durée de vie |
|---|---|---|
| un fichier dans `/usr` | `sudo bootc usr-overlay`, puis modifier | jusqu'au redémarrage |
| un paquet | `sudo rpm-ostree install --apply-live <paquet>` | persistant, visible dans `rpm-ostree status` |
| un réglage dans `/etc` | modifier directement | persistant |
| un paramètre du noyau | `sudo rpm-ostree kargs --append=<karg>` | persistant |

Les mises à jour continuent : les bidouilles persistantes sont rejouées par-dessus chaque nouvelle image. On peut donc laisser Claire utiliser la machine quelques jours pour voir si le correctif tient.

### 2. Reporter dans l'image

Voir [Modifier l'image](#modifier-limage). Pull request, merge, puis attendre que le laptop applique l'image (ou `sudo bootc upgrade` puis redémarrer).

### 3. Nettoyer et vérifier

```sh
sudo rpm-ostree reset                  # retire paquets ajoutés et overrides locaux
sudo rpm-ostree kargs --delete=<karg>  # si le karg est maintenant dans kargs.d
sudo ostree admin config-diff          # tout ce qui diffère de l'image dans /etc
rpm-ostree status                      # aucun « LayeredPackages » ni « LocalPackages »
```

Pour remettre un fichier de `/etc` à la version de l'image : le copier depuis `/usr/etc/`.

Seules la dérive de `/etc` et les paquets ajoutés sont possibles : ces commandes les montrent entièrement.

## Revenir en arrière

- **À distance** : `sudo bootc rollback`, puis redémarrer. Le déploiement précédent redevient le défaut.
- **Sur place** : au démarrage, choisir la deuxième entrée du menu.
- **Garder une version sûre** : `sudo ostree admin pin 0` épingle le déploiement courant (il ne sera pas supprimé par les mises à jour). `sudo ostree admin pin --unpin <n>` pour le libérer.
- **Revenir à Aurora d'origine** : `sudo bootc switch ghcr.io/ublue-os/aurora:stable`.

## Tester dans une VM

Sur une de mes machines Arch (libvirt, virt-manager, OVMF et swtpm viennent de `arch-config`). La VM `aurora-test` reproduit l'installation réelle : ISO Aurora, Secure Boot, puis `bootc switch`.

```fish
set -x LIBVIRT_DEFAULT_URI qemu:///system
set d /var/lib/libvirt/images/aurora-test
sudo mkdir -p $d; cd $d
sudo curl -fLO https://dl.getaurora.dev/aurora-stable-webui-x86_64.iso
sudo curl -fLO https://dl.getaurora.dev/aurora-stable-webui-x86_64.iso-CHECKSUM
sha256sum -c aurora-stable-webui-x86_64.iso-CHECKSUM

# L'OVMF d'Arch n'a pas les clés Microsoft : sans elles, Secure Boot n'est pas appliqué.
# On en fait une copie des variables EFI avec les clés enregistrées.
uvx --from virt-firmware virt-fw-vars --input /usr/share/edk2/x64/OVMF_VARS.4m.fd \
    --output /tmp/OVMF_VARS.ms.4m.fd --enroll-redhat --secure-boot
sudo install -m644 /tmp/OVMF_VARS.ms.4m.fd $d/

virsh net-start default   # si le réseau NAT est inactif
virt-install --name aurora-test --osinfo fedora-unknown \
    --memory 8192 --vcpus 6 --cpu host-passthrough --machine q35 --features smm.state=on \
    --boot loader=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd,loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template=$d/OVMF_VARS.ms.4m.fd \
    --disk path=$d/disk.qcow2,size=64,format=qcow2,bus=virtio,discard=unmap \
    --cdrom $d/aurora-stable-webui-x86_64.iso \
    --network network=default --graphics spice --video virtio \
    --noautoconsole
virt-manager --connect qemu:///system --show-domain-console aurora-test
```

Puis suivre [Installer la machine](#installer-la-machine). Dans la VM, tester :
- la passphrase à l'invite LUKS avec des lettres qui changent de place entre QWERTY et AZERTY (a, q, z, w, m) ;
- l'autologin et le wallet ouvert (vérifié le 09/10/2026) ;
- les Flatpaks préinstallés ;
- un `bootc rollback`.

Ce qui ne se teste pas en VM : le matériel du Framework (PSR, audio, empreinte, veille).

Pour tester une modification avant de la publier, la VM suit l'image locale via un petit registre sur l'hôte, joignable seulement depuis l'hôte (`127.0.0.1`) et le réseau des VM (`192.168.122.1`). Docker refuse de pousser en HTTP ailleurs que vers `localhost`, d'où les deux adresses.

Une fois, sur l'hôte :
```fish
docker run -d --restart=unless-stopped --name aurora-registry \
    -p 127.0.0.1:5000:5000 -p 192.168.122.1:5000:5000 registry:2
```

Une fois, dans la VM (après l'installation) :
```sh
printf '[[registry]]\nlocation = "192.168.122.1:5000"\ninsecure = true\n' | sudo tee /etc/containers/registries.conf.d/50-banc-de-test.conf
sudo bootc switch 192.168.122.1:5000/aurora-claire:latest
```

À chaque itération : sur l'hôte, [construire](#construire-en-local) puis pousser ; dans la VM, mettre à jour. Seules les couches modifiées transitent.
```fish
docker build -f Containerfile -t localhost:5000/aurora-claire . && docker push localhost:5000/aurora-claire
```
```sh
sudo bootc upgrade && systemctl reboot
```

Revenir ensuite sur l'image publiée : `sudo bootc switch ghcr.io/crocmagnon/aurora-claire:latest`.

Repartir de zéro :
```fish
virsh destroy aurora-test; virsh undefine aurora-test --nvram
sudo rm -f /var/lib/libvirt/images/aurora-test/disk.qcow2
```

## ujust

`ujust` est le lanceur de recettes d'Universal Blue : des scripts prêts à l'emploi, livrés dans l'image (`/usr/share/ublue-os/just/`). `ujust` seul affiche la liste ; la plupart des recettes demandent confirmation avant d'agir.

**Utiles pour l'entretien :**

| Commande | Effet |
|---|---|
| `ujust update` | met à jour tout de suite : système, Flatpaks, Homebrew (ce que uupd fait seul) |
| `ujust toggle-updates` | affiche et active ou coupe les mises à jour automatiques (doivent rester actives) |
| `ujust changelogs` | changements de la dernière image Aurora |
| `ujust check-local-overrides` | fichiers de `/etc` qui diffèrent de l'image (même rôle que `ostree admin config-diff`, en plus lisible) |
| `ujust logs-this-boot`, `ujust logs-last-boot` | journal du démarrage courant ou précédent (utile après un plantage) |
| `ujust device-info` | rassemble les infos de la machine sur un pastebin, pour demander de l'aide |
| `ujust bios`, `ujust bios-info` | redémarrer dans le BIOS, version du BIOS |
| `ujust check-idle-power-draw` | consommation au repos (autonomie) |
| `ujust clean-system` | libère de la place : conteneurs inutilisés, Flatpaks orphelins, caches rpm-ostree et Homebrew (garde le déploiement de secours) |

**À ne pas lancer sur la machine de Claire :**

| Commande | Pourquoi |
|---|---|
| `ujust rebase-helper`, `ujust toggle-devmode` | basculent sur une autre image Aurora : le laptop quitterait `aurora-claire` et ses réglages |
| `ujust toggle-tailscale` | coupe Tailscale, donc mon accès de dépannage |
| `ujust toggle-tpm2` | déverrouillage LUKS par TPM : écarté (voir [Les choix faits](#les-choix-faits)) |
| `ujust powerwash` | remise à zéro de la machine |
| `ujust aurora-cli`, `ujust bbrew`, `ujust install-fonts` | outils et polices via Homebrew, sans intérêt pour Claire (sans danger en revanche) |
| `ujust enroll-secure-boot-key` | pour les pilotes Nvidia, inutile ici |

Après un `rebase-helper` ou un `toggle-devmode` par erreur : `sudo bootc switch ghcr.io/crocmagnon/aurora-claire:latest`, puis redémarrer.

## Aide-mémoire

| Je veux… | Commande (sur le laptop) |
|---|---|
| voir l'image et les déploiements | `rpm-ostree status` ou `sudo bootc status` |
| forcer la mise à jour maintenant | `sudo bootc upgrade` puis redémarrer (ou `ujust update`) |
| revenir à l'image précédente | `sudo bootc rollback` puis redémarrer |
| voir la dérive de `/etc` | `sudo ostree admin config-diff` |
| retirer les paquets ajoutés localement | `sudo rpm-ostree reset` |
| voir ou changer les paramètres du noyau | `rpm-ostree kargs`, `sudo rpm-ostree kargs --append=… / --delete=…` |
| rendre `/usr` modifiable jusqu'au redémarrage | `sudo bootc usr-overlay` |
| voir les journaux de mise à jour | `journalctl -u uupd.service` |
| prochaine mise à jour automatique | `systemctl list-timers uupd.timer` |
| lister les commandes Aurora | `ujust` (voir [ujust](#ujust)) |
| voir la dérive de `/etc`, version lisible | `ujust check-local-overrides` |
