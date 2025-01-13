# Script de sauvegarde ZFS/*n*x

 Adresse du projet: https://forge.centrale-marseille.fr/projects/sauvegardes

## Features

- agent-less (only ssh, /bin/sh, rsync and/or zfs required on clients)
- backup server initiate the backup - does not have to be accessible from clients
- using UFS snapshots for consistent backups on FreeBSD
- /bin/sh script (can run on any bourne shell)
- server on FreeBSD/ZFS (may work elsewhere but untested)
- clients tested: Linux/OpenBSD/FreeBSD (any unix-like OS should work)
- FreeBSD jails can be saved apart (and not depend on their host for restauration)
- proxmox: VM's can be saved apart (with local disks on proxmox)
- ZFS-powered: keep snapshot(s) for each backup session

## Dependencies
- rsync for any non-zfs filesystem
- fping
- mutt for reporting
- mbuffer advised (not mandatory)
- root access on clients, with ssh key only

