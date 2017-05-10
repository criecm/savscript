#### Script de sauvegarde ZFS/*nix ####

 Adresse du projet: https://forge.centrale-marseille.fr/projects/sauvegardes

- creez une paire de cles ssh pour la sauvegarde: (la cle publique sera installee sur chaque client dans `~root/.ssh/authorized_keys`)

  `ssh-keygen -C "savscript@$(hostname -s)" -N '' -f id_sav`

- copiez savscript.conf.dist en savscript.conf
- editez savscript.conf (`SSH_KEY`,`SAVDIR`, …)
- utilisez `./tools/nouvelle_machine.sh` pour ajouter une machine dans machines.d/ automatiquement
- lancez `./savscript.sh` (avec -v en cas de problème)
- ajoutez au crontab une ligne du type:

  `32 23 * * *	root	/chemin/vers/savscript.sh`
 
### C'est quoi ce truc ? ###

- pas de client "lourd"
- pur /bin/sh, ssh, rsync (du connu :) et ZFS !
- prevu/testé pour un serveur FreeBSD
- a installer: mbuffer, rsync, fping, mutt
