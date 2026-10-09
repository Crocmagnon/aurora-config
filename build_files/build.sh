#!/bin/bash
# Modifications de l'image Aurora. Les fichiers de system_files/ sont copiés tels quels à la racine.
set -ouex pipefail

cp -avf /ctx/system_files/. /

# steam-devices : règles udev des manettes, que le Flatpak Steam ne peut pas poser.
# fuse-libs : FUSE 2, dont l'AppImage pCloud a besoin. hunspell-fr : correcteur orthographique.
dnf5 install -y steam-devices fuse-libs hunspell-fr

# Wallet ouvert à l'autologin avec la passphrase LUKS (même principe que arch-config) :
# systemd-cryptsetup laisse la passphrase dans le trousseau du noyau, plasmalogin.service en
# hérite (KeyringMode=inherit, dans system_files), pam_systemd_loadkey la passe à pam_kwallet5.
# Le fichier PAM vient du paquet : on y insère la ligne au lieu de le copier, et le build
# échoue si la ligne pam_kwallet5 a disparu.
# Fedora le livre dans /usr/lib/pam.d (aucune copie dans /etc/pam.d, qui aurait priorité).
pam=/usr/lib/pam.d/plasmalogin-autologin
sed -i '0,/^-\?auth.*pam_kwallet5\.so/s//auth        optional    pam_systemd_loadkey.so\n&/' "$pam"
grep -q pam_systemd_loadkey "$pam"
cat "$pam"
