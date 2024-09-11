# Script de sauvegarde ZFS/*n*x

 Adresse du projet: https://forge.centrale-marseille.fr/projects/sauvegardes

## Features

- agent-less (ssh, /bin/sh, rsync or zfs)
- /bin/sh scripted
- server on FreeBSD/ZFS (may work elsewhere)
- clients tested: Linux/OpenBSD/FreeBSD (any unix-like OS should work)
- FreeBSD jails can be saved apart (and not depend on their host)

## Dependencies
- rsync for any non-zfs client
- fping
- mutt for reporting
- mbuffer advised (not mandatory)
- root access on clients, with ssh key only

## HOWTO

### new backup server
1. git clone this
2. Create a new ssh key pair only for backups, this key will be authorized from this host only

  `ssh-keygen -C "savscript@$(hostname -s)" -N '' -f id_sav`

3. copy savscript.conf.dist to savscript.conf
4. edit savscript.conf (`SSH_KEY`,`SAVDIR`, …)
5. add a client and test
6. add to crontab

  `32 23 * * *	root	/path/to/savscript.sh`
 

### new client
1. use `./tools/nouvelle_machine.sh my.client` to create a config file in machines.d/ and deploy ssh key on clients
2. launch `./savscript.sh` (with `-v` if needed)


