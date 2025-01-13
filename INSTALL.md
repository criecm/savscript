## HOWTO

### on your backup server
1. git clone this
2. Create a new ssh key pair only for backups, this key will be authorized from this host only

  `ssh-keygen -C "savscript@$(hostname -s)" -N '' -f id_sav`

3. copy savscript.conf.dist to savscript.conf
4. edit savscript.conf (`SSH_KEY`,`SAVDIR`, …)
5. add a client and test
6. add to crontab

  `32 23 * * *	root	/path/to/savscript.sh`
 
### for each new client
1. use `./tools/nouvelle_machine.sh my.client` to:
  - create a config file in machines.d/my.client.conf
  - deploy ssh key on client's .ssh/authorized_keys
2. edit machines.d/my.client.conf to enable/disable features (default should be ok)
3. you may launch manually `./savscript.sh my.client` (with `-v` if needed)

