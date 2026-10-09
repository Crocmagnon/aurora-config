#!/bin/bash
# Modifications de l'image Aurora. Les fichiers de system_files/ sont copiés tels quels à la racine.
set -ouex pipefail

# Fichiers à root : ne pas reprendre le propriétaire des sources (en local, ce serait
# l'uid 1000, celui de Claire sur le laptop).
cp -rvf --no-preserve=ownership /ctx/system_files/. /

# steam-devices : règles udev des manettes, que le Flatpak Steam ne peut pas poser.
# fuse-libs : FUSE 2, dont l'AppImage pCloud a besoin. hunspell-fr : correcteur orthographique.
dnf5 install -y steam-devices fuse-libs hunspell-fr

# Wallet ouvert à l'autologin avec la passphrase LUKS (même principe que arch-config) :
# systemd-cryptsetup laisse la passphrase dans le trousseau du noyau, plasmalogin.service en
# hérite (KeyringMode=inherit, dans system_files), pam_systemd_loadkey la passe à pam_kwallet5.
# Le fichier d'autologin de Fedora n'appelle pam_kwallet5 qu'en phase session : on ajoute la
# phase auth, qui récupère la passphrase, juste avant « auth include postlogin » (comme dans
# /usr/lib/pam.d/plasmalogin). Le fichier vient du paquet : on le modifie au lieu de le copier,
# et le build échoue si la ligne d'ancrage a disparu. Fedora le livre dans /usr/lib/pam.d, sans
# copie dans /etc/pam.d, qui aurait priorité.
pam=/usr/lib/pam.d/plasmalogin-autologin
sed -i '/^auth\s\+include\s\+postlogin/i auth        optional    pam_systemd_loadkey.so\n-auth       optional    pam_kwallet5.so' "$pam"
grep -q '^auth.*pam_systemd_loadkey\.so' "$pam"
cat "$pam"

# Menu GRUB visible 5 s (voir le service).
systemctl enable aurora-config-grub.service

# Thème Breeze de KDE pour GRUB. Le paquet s'installe dans /boot, hors de l'image : on l'extrait
# sous /usr, et aurora-config-grub.service le recopie dans /boot. Pas de traduction : ses polices
# n'ont que l'ASCII.
dnf5 download -y --destdir=/tmp/breeze grub2-breeze-theme
(cd /tmp/breeze && rpm2cpio grub2-breeze-theme-*.rpm | cpio -idm --quiet)
mkdir -p /usr/lib/aurora-config/grub-themes
mv /tmp/breeze/boot/grub2/themes/breeze /usr/lib/aurora-config/grub-themes/
