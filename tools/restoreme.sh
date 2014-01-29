#!/bin/sh
#
# script de restauration systeme via livefs FreeBSD
#
# ce script est concu pour etre appele via une cle ssh
#
#. /usr/local/admin/utils/common/common.sh.inc

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

savpath=$(realpath "$(dirname $0)/..")
. $savpath/rsync_serveurs.conf || exit 1

if [ -z "$host" ]; then
  echo "usage: $0 host [dest]"
  echo "  ... will restore host (on \$dest, or on \$host if no \$dest)"
  erreur "manque le nom de machine"
fi

if [ -f $MACHINESDIR/$host.conf ]; then
  . $MACHINESDIR/$host.conf
  dest=$(grep '^DEST=' $MACHINESDIR/$host.conf | cut -d= -f1)
  srcdir=$SAVDESTBASE/$NAME
  srczfsvol=$SAVZFSBASE/$NAME
else
  erreur "$SAVDESTBASE/$host non existant"
fi

if [ ! -d "$srcdir" ] || ! zfs list -H -oname $srczfsvol; then
  erreur "$srcdir ou $srczfsvol inexistant"
fi

. $savpath/lib/rsync_serveurs.inc.sh

fping -t 1 $dest || erreur "$dest ne pong pas :("

echo "Restauration de \"$host\" from $(hostname -s) to \"$dest\""
if dialog --yesno "La restauration doit-elle se faire en FULL-ZFS (si non, rsync)?" 0 0; then
  # exclusions
  exec 3>&1
  zfs list -H -o name,mountpoint -t filesystem -S name -r ${srczfsvol} | while read n m; do is_excluded ${n%@*} || is_excluded ${m} || zfs list -H -oname,mountpoint -r -d1 -tfilesystem,snapshot -Sname $n ; done > /tmp/zfssnaps.$$.list
  AEXCLURE=$(fgrep -v @ /tmp/zfssnaps.$$.list | awk '{printf("%s %s off\n",$1,$2);}' | xargs dialog --backtitle "Choix des volumes a exclure" --title "Exclusions" --checklist "Cochez les volumes a exclure" 0 0 0 2>&1 1>&3)
  echo "Choix du snapshot a utiliser pour la restauration:"
  SNAPS=""
  for snap in $(grep ^${srczfsvol}@ /tmp/zfssnaps.$$.list | cut -f1); do
    notsnap=''
    for v in $(fgrep -v @ /tmp/zfssnaps.$$.list); do
      if ! fgrep -q $v@$snap /tmp/zfssnaps.$$.list; then
        notsnap=$v
        break
      fi
    done
    [ -z "$notsnap" ] && SNAPS=$SNAPS" "$snap
  done
  SNAP=$(dialog --backtitle "Choix du snapshot" --title "Choisis le bon :)" --nocancel --menu 0 0 0 0 $SNAPS 2>&1 1>&3)
  test -n "$SNAP" || exit 1
  if dialog --yesno "On envoie $srczfsvol@$SNAP sur le pool zroot de $host (en ecrasant tout !) ?" 0 0; then
    /usr/local/admin/utils/freebsd/zfs_sync_vol -k /root/.ssh/id_rsyncsav -CRu -r $SNAP ${srczfsvol} zroot@${dest} || exit 1
  fi
else
  echo "${host}: restauration rsync:"
  if dialog --yesno "On rsync $srcdir/ sur $dest/mnt/ (en ecrasant tout !) ?" 0 0; then
    echo "rsync -a --exclude .zfs/ --exclude .snap/ -e 'ssh -i /root/.ssh/id_rsyncsav' ${srcdir}/ root@${dest}:/mnt/"
    rsync -a --exclude .zfs/ --exclude .snap/ -e 'ssh -i /root/.ssh/id_rsyncsav' ${srcdir}/ root@${dest}:/mnt/
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

