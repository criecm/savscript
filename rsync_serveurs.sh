#!/bin/sh
#
# Script de sauvegardes des serveurs *n*x ECM.
#
# Principe: un script/serveur dans un repertoire rsync_serveurs/
#
# TODO: paralleliser un peu (mais pas trop !)
#   eg: https://github.com/buganini/brackets
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
RSYNC=${RSYNC:-"/usr/local/bin/rsync"}
RSYNC_RSH="ssh -i /root/.ssh/id_rsyncsav"
RSYNC_OPTS='-H -q -4 -aux --delete --exclude .snap/ --exclude .zfs/'

export PATH RSYNC RSYNC_RSH RSYNC_OPTS

# max n. of concurrent jobs
MAXJOBS=${MAXJOBS:-10}

if [`mount | grep '/sav' | wc -l 2> /dev/null` -eq 0 ]; then
/sbin/mount /sav || exit 1;
#UMOUNT=1
fi

mydir=$(dirname $0)

waitupto() {
  MYMAX=${1:-$MAXJOBS}
  while [ $(pgrep -f '/bin/sh '$mydir'/rsync_serveurs.sh ' | wc -l) -gt $(( MYMAX + 1 )) ]; do
    sleep 3
  echo -n "."
  done
}

# s'il y a des arguments, on execute les fichiers correspondants (rsync_serveurs/$arg.rsync)
if [ $# -gt 0 ]; then
  while [ $# -gt 0 ]; do
    if [ -f $mydir/rsync_serveurs/$1.rsync ]; then
      lockfile=${TMPDIR:-/tmp}/rsync.$1.encours
      err=""
      time lockf -t 0 $lockfile /bin/sh $mydir/rsync_serveurs/$1.rsync
      case $? in
        73)
          err="Cannot create ${TMPDIR:-/tmp}/rsync.$1.encours"
        ;;
        75)
          err="$mydir/rsync_serveurs/$1.rsync already running"
        ;;
        71)
          err="System error (?)"
        ;;
        70)
          err="Problem with $mydir/rsync_serveurs/$1.rsync"
        ;;
      esac
      if [ ! -z "$err" ]; then
        echo "$err"
        logger -t ${0##*/} -p user.err "$err"
      fi
    else
      echo "$mydir/rsync_serveurs/$1.rsync n'existe pas."
    fi
    shift
  done
else
  # sinon, executer les fichiers *.rsync dans rsync_serveurs/
  echo "rsync_serveurs: GO "$(date)
  TBEGINALL=$(date +%s)
  for file in $mydir/rsync_serveurs/*.rsync; do
    waitupto
    serv=${file##*/}
    serv=${serv%.rsync}
    echo "rsync_serveurs: debut $serv "$(date)
    date >> /var/log/rsync_serveurs.$serv.log
    $0 $serv >> /var/log/rsync_serveurs.$serv.log 2>&1 &
  done
  waitupto 0
  echo "rsync_serveurs: THE END ("$(($(date +%s) - $TBEGINALL))"s)"
fi

