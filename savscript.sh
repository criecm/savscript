#!/bin/sh
#
# Script de sauvegardes des serveurs *n*x ECM.
#
# Principe: une conf/client dans un repertoire machines.d/
#
# TODOS: 
#  - MAJ script restauration (ZFS slash/root, verifier autres systemes, pb cle ssh, orig:mountpoint)
#  - script restauration de jail
#  - menage snapshots (prevu pour un snapshot recursif -> c'est a lui de l'etre)
#  - UFS: faire les snapshots au debut, les monter dans /tmp/mntsav (ou /mnt/tmpsav?) et y lancer rsyncd
#
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
mydir=$(dirname $0)

if [ -z "$CONFIG_LOADED" ]; then
  . $mydir/savscript.conf
  for i in RSYNC_OPTS SSH_KEY SAVDESTBASE ADMINMAIL MACHINESDIR FSTYPES; do
    if ! eval "test -n \"\$$i\""; then
      echo "manque $i dans la savscript.conf" >&2
      exit 1
    fi
  done
  if [ ! -d $MACHINESDIR ]; then
    echo "Repertoire $MACHINESDIR inexistant \!" >&2
    exit 1
  fi
  if [ ! -r $SSH_KEY ]; then
    echo "cle ssh \"$SSH_KEY\" illisible ou inexistante" >&2
    exit 1
  fi
  export CONFIG_LOADED=YES
fi

while getopts d:h option
do
  case $option in
    d) DEBUG=$OPTARG ;;
    h) echo "usage: $0 [-d n] [serveur [serveur serveur ...]]"
       echo "  -d n: debug. 4=affiche les commande au lieu de les lancer. defaut 0"
       echo "  serveur: le fichier $MACHINESDIR/$serveur.conf sera utilise"
       exit 0
    ;;
  esac
done
shift $(expr $OPTIND - 1)

# binaire rsync
RSYNC=${RSYNC:-"$(which rsync)"}
# options par defaut pour rsync
RSYNC_OPTS=${RSYNC_OPTS:-"-H -q -aux --delete --exclude .snap/ --exclude .zfs/"}
# commande ssh distante
REMOTE_COMMAND=${REMOTE_COMMAND:-"ssh -i $SSH_KEY"}
# volume zfs des sauvegardes
SAVZFSBASE=${SAVZFSBASE:-$(zfs list -H -o name "$SAVDESTBASE")}
# mail a prevenir en cas de probleme
ADMINMAIL=${ADMINMAIL:-"dgeo@ec-m.fr"}
# repertoire de base pour le stockage temporaire des resultats
TRACESDIRBASE=${TRACESDIRBASE:-"/tmp/LOG.SAUV_TRACES"}
# max n. of concurrent jobs
MAXJOBS=${MAXJOBS:-10}
# syslog facility
export SYSLOG_FACILITY=${SYSLOG_FACILITY:-"user"}
# syslog 'program'
export SYSLOG_TAG=${SYSLOG_TAG:-"SAUVEGARDE"}
# debug
DEBUG=${DEBUG:-0}

if ! zfs list -H -o name "$SAVZFSBASE" > /dev/null; then
  echo "Impossible de trouver le volume ZFS \"$SAVZFSBASE\"" >&2
  exit 1
fi

TRACES=$TRACESDIRBASE.$$
if [ -e "$TRACES" ]; then
  rm -rf $TRACES
fi
mkdir $TRACES

if [ $DEBUG -gt 3 ]; then
  DEBUGADONF=1
  if [ $DEBUG -ge 2 ]; then
    MAXJOBS=1
  fi
fi

export PATH RSYNC RSYNC_OPTS SAVDESTBASE SAVZFSBASE mydir TRACES REMOTE_COMMAND SSH_KEY DEBUG MACHINESDIR FSTYPES ZFS_SYNC_VOL ZFS_SNAP_MAKE

## checks
if ! mount | grep -q 'on '$SAVDESTBASE ; then
/sbin/mount /sav || exit 1;
#UMOUNT=1
fi

## fonction de parallelisation
waitupto() {
  MYMAX=${1:-$MAXJOBS}
  while [ $(( $(pgrep -f '/bin/sh '$mydir'/lib/save_one.sh' | wc -l) )) -gt $(( MYMAX )) ]; do
    sleep 3
#  echo -n "."
  done
}

. $mydir/lib/log.inc.sh

# s'il y a des arguments, on lance un save_one.sh pour chacun
if [ $# -gt 0 ]; then
  while [ $# -gt 0 ]; do
    # NEW
    if [ -f $MACHINESDIR/$1.conf ]; then
      lockfile=${TMPDIR:-/tmp}/sauv.$1.encours
      err=""
      if [ $DEBUG -gt 0 ]; then syslogue "debug" "time lockf -t 0 $lockfile /bin/sh ${DEBUGADONF:+-x }$mydir/lib/save_one.sh $MACHINESDIR/$1.conf"; fi
      time lockf -t 0 $lockfile /bin/sh ${DEBUGADONF:+-x }$mydir/lib/save_one.sh $MACHINESDIR/$1.conf
      case $? in
        73)
          err="Cannot create lockfile $lockfile"
        ;;
        75)
          err="$mydir/lib/save_one.sh $MACHINESDIR/$1.conf already running ($lockfile)"
        ;;
        71)
          err="System error (?)"
        ;;
        70)
          err="Problem with $mydir/lib/save_one.sh $MACHINESDIR/$1.conf"
        ;;
      esac
      if [ ! -z "$err" ]; then
        syslogue "error" "$err"
      fi
    else
      syslogue "error" "$MACHINESDIR/$1.conf n'existe pas."
    fi
    shift
  done
else
  # sinon, lister les fichiers *.conf dans machines.d/
  # et se lancer pour chacun
  syslogue "info" "savscript: GO $(date)"
  TBEGINALL=$(date +%s)
  for file in $mydir/machines.d/*.conf; do
    waitupto
    serv=$(grep ^NAME $file|cut -d= -f2)
    syslogue "info" "savscript: debut ${serv} "$(date)
    date >> /var/log/savscript.$serv.log
    /bin/sh $mydir/lib/save_one.sh $file >> /var/log/savscript.$serv.log 2>&1 &
  done
  waitupto 0
  TOTALS=$(($(date +%s) - $TBEGINALL))
  syslogue "info" "savscript: THE END ($(($TOTALS / 3600))h$(($TOTALS % 3600 / 60))m$(($TOTALS % 3600 % 60))s)"
fi
if [ -s $TRACES/msg ]; then
  if [ ! -z "$ADMINMAIL" ]; then
    cat $TRACES/msg | mutt -s "[${SYSLOG_TAG}] Problemes avec" $ADMINMAIL -a $(find $TRACES ! -size 0 -type f)
  else
    syslogue "error" "Problemes avec:"
    cat $TRACES/msg | while read line; do syslogue "error" "  $line" ; done
  fi
else
  if [ $DEBUG -le 1 ]; then rm -rf $TRACES; fi
fi

