# Script de sauvegarde ZFS/*n*x

 Adresse du projet: https://forge.centrale-marseille.fr/projects/sauvegardes

## Features

- aucune installation sur le "client" (/bin/sh, rsync ou zfs)
- pur /bin/sh, ssh, rsync (du connu :) et ZFS !
- prevu/utilisé avec un serveur FreeBSD/ZFS et clients OpenBSD, FreeBSD, Linux divers
- sauvegarde des jails freebsd a part (iocage ou jails "standard")
- dependences côté serveur: rsync, fping, mutt (mbuffer conseillé)

## HOWTO

### nouveau serveur
1. git clone
2. creez une paire de cles ssh pour la sauvegarde: (la cle publique sera installee sur chaque client dans `~root/.ssh/authorized_keys`)

  `ssh-keygen -C "savscript@$(hostname -s)" -N '' -f id_sav`

3. copiez savscript.conf.dist en savscript.conf
4. editez savscript.conf (`SSH_KEY`,`SAVDIR`, …)
5. ajoutez au crontab une ligne du type:

  `32 23 * * *	root	/chemin/vers/savscript.sh`
 

### nouveau client
1. utilisez `./tools/nouvelle_machine.sh` pour ajouter une machine dans machines.d/ automatiquement
2. lancez `./savscript.sh` (avec -v en cas de problème)


