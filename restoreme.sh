#!/bin/sh
#
# script de restauration systeme via livefs FreeBSD
#
# ce script est concu pour etre appele via une cle ssh
#
. /usr/local/admin/utils/common/common.sh.inc

host=""
dest=""
if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
  host=${SSH_ORIGINAL_COMMAND% *}
  dest=${SSH_ORIGINAL_COMMAND#* }
fi
if [ -z "$host" -o -z "$dest" -a $# -ge 1 ]; then
  host=$1
  shift
  if [ $# -eq 1 ]; then
    dest=$1
  else
    dest=$host
  fi
fi

erreur() {
  echo $@
  exit 1
}

if [ -z "$host" -o ! -d "/sav/$host" ]; then
  echo "usage: $0 host [dest]"
  echo "  ... will restore host (on \$dest, or on \$host if no \$dest)"
  erreur "manque le nom de machine"
fi

fping -t 1 $dest || erreur "$dest ne pong pas :("

echo "Restauration de \"$host\" from shaun to \"$dest\""
test -d /sav/${host} || erreur "/sav/$host n'existe pas sur shaun:(";
if mount -t zfs | grep "on /sav/${host}" && zfs list -r disques/sav/$host && askok "Restaurer les volumes ZFS tels quels(y) ou via rsync(n) ?"; then 
  echo "Choix du snapshot a utiliser pour la restauration:"
  exec 3>&1
  SNAP=$(zfs list -H -o name -t snapshot -S name -r disques/sav/${host}| sed 's/^.*@//' | awk '{printf("%s %s\n",$1,$1);}' | xargs dialog --backtitle "Choix du snapshot" --title "Choisis le bon :)" --nocancel --menu 0 0 0 0 2>&1 1>&3)
  test -n "$SNAP" || exit 1
  if askok "On envoie disques/sav/$host@$SNAP sur le pool zroot de $host (en ecrasant tout !) ?"; then
    /usr/local/admin/utils/freebsd/zfs_sync_vol -k /root/.ssh/id_rsyncsav -CRu -r $SNAP disques/sav/${host} zroot@${dest} || exit 1
  fi
else
  echo "${host}: restauration rsync:"
  if askok "On rsync disques/sav/$host/ sur $dest/mnt/ (en ecrasant tout !) ?"; then
    echo "rsync -a --exclude .zfs/ --exclude .snap/ -e 'ssh -i /root/.ssh/id_rsyncsav' /sav/${host}/ root@${dest}:/mnt/"
    rsync -a --exclude .zfs/ --exclude .snap/ -e 'ssh -i /root/.ssh/id_rsyncsav' /sav/${host}/ root@${dest}:/mnt/
  fi
  case "$?" in 
    23|24|0) 
      exit 0; 
    ;; 
    *)
      exit 1; 
    ;; 
  esac
fi

