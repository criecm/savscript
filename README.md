#### Script de sauvegarde ZFS/*n*x

 Adresse du projet: https://forge.centrale-marseille.fr/projects/sauvegardes

- creez une paire de cles ssh pour la sauvegarde: (la cle publique sera installee sur chaque client dans `~root/.ssh/authorized_keys`)

  `ssh-keygen -C "savscript@$(hostname -s)" -N '' -f id_sav`

- copiez savscript.conf.dist en savscript.conf
- editez savscript.conf (`SSH_KEY`,`SAVDIR`, …)
- utilisez `./tools/nouvelle_machine.sh` pour ajouter une machine dans machines.d/ automatiquement
- lancez `./savscript.sh` (avec -v en cas de problème)
- ajoutez au crontab une ligne du type:

  `32 23 * * *	root	/chemin/vers/savscript.sh`
 
### Particularités

- aucune installation sur le "client" (/bin/sh, rsync ou zfs)
- pur /bin/sh, ssh, rsync (du connu :) et ZFS !
- prevu/utilisé avec un serveur FreeBSD/ZFS et clients OpenBSD, FreeBSD, Linux divers
- sauvegarde des jails freebsd a part (iocage ou jails "standard")
- dependences côté serveur: rsync, fping, mutt (mbuffer conseillé)
