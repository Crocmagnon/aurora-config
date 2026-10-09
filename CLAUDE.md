# CLAUDE.md

Image bootc Aurora du laptop de Claire. Le `README.md` (en français) décrit l'image, l'installation et le workflow de correctif : le garder à jour à chaque changement.

- Préférer `system_files/usr/lib/...` à `system_files/etc/...` : `/etc` est fusionné en trois voies, et une modification locale y masque l'image pour toujours. N'aller dans `/etc` que si le logiciel ne lit rien sous `/usr` (ex. `plasmalogin.conf.d`).
- Paramètres noyau : `system_files/usr/lib/bootc/kargs.d/*.toml`.
- Réglages repris de `arch-config` (`~/Projects/codeberg.org/Crocmagnon/arch-config`) : citer l'origine en commentaire.
- Un secret à versionner passe par git-crypt. La clé de signature cosign n'est que dans le secret GitHub `SIGNING_SECRET` ; on la régénère au besoin (`cosign generate-key-pair`, puis remplacer `cosign.pub`).
- Le build tourne sur GitHub Actions (pas de podman sur l'hôte) : `gh run watch` après un push.
