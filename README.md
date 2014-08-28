#### Script de sauvegarde ZFS/*nix ####

- creez une paire de cles ssh pour la sauvegarde
  <<<  ssh-keygen ~/.ssh/id_rsa_savscript >>>
- copiez rsync_serveurs.conf.dist en rsync_serveurs.conf
- editez rsync_serveurs.conf
- utilisez ./tools/nouvelle_machine.sh pour ajouter une machine dans machines.d/ automatiquement
- lancez ./rsync_serveurs.sh (avec -v en cas de problème)
- ajoutez au crontab une ligne du type:
  <<< 32 23 * * *	root	/chemin/vers/rsync_serveurs.sh >>>
 

