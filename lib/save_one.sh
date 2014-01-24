#!/bin/sh
#
# SCRIPT TEMPLATE - ALL UNIX OS
#
if [ -z "$CONFIG_LOADED" ]; then
  echo "ne pas utiliser directement"
  echo " utiliser $mydir/rsync_serveurs.sh machine"
  exit 1
elif [ $# -ne 1 -o ! -f "$1" ]; then
  syslogue "error" "Argument \"$1\" non valide"
  exit 1
fi

. $1
ZFSDEST=${ZFSDEST:-"$SAVZFSBASE/$NAME"}
DESTDIR=${DESTDIR:-"$SAVDESTBASE/$NAME"}
JAILSZFSDEST=${JAILSZFSDEST:-"$SAVZFSBASE/jails"}
JAILSDESTDIR=${JAILSDESTDIR:-"$SAVDESTBASE/jails"}
RSYNC_PORT=${RSYNC_PORT:-42873}
RSYNC_DIRECT=${RSYNC_DIRECT:-"YES"}

. $mydir/lib/rsync_serveurs.inc.sh

DEST=${DEST:-$NAME}

if init_srv $DEST; then
    syslogue "info" "($NAME): start"

    if [ ! -z "$ZPOOLS" ]; then
        for pool in $ZPOOLS; do
            zfs_presnap $pool
        done
    fi

    myret=0

    # JAILS
    if [ ! -z "$SAV_JAILS" ]; then
        if [ ! -z "$JAILS" ]; then
            for jaildir in $JAILS; do
                if ! is_excluded $jaildir; then
                    get_jail $jaildir
                    myret=$(( $ret + $? ))
                fi
            done
        fi
    fi

    # FULL ZFS SCENARIO
    if [ "$FULLZFS" = "YES" ]; then
        # tout est en ZFS: cool :)
        for testfs in $ZFSFSES; do
            is_excluded ${testfs%|*} && now_exclude_zfs ${testfs#*|}
        done 
        # si aucune exclusion + c'est le seul zpool, alors on lance en un coup
        if [ -n "$ONEZPOOL" ]; then
            syslogue "info" "($NAME) FULLZFS: sauvegarde du pool ZFS $ONEZPOOL"
            get_zfs / $ZFSDEST $ONEZPOOL
            myret=$(( $myret + $? ))
        else
            # si la racine est en ZFS, le pool ZFS vient a la racine
            if [ -n "$ZFSSLASH" ]; then
                get_zfs / $ZFSDEST ${ZFSSLASH%%/*}
            fi
            for fs in $ZFSFSES; do
                if ! is_excluded ${fs%|*} && ! is_excluded ${fs#*|} && [ "${fs%|*}" != "none" ]; then
                    get_zfs ${fs%|*} 
                    myret=$(( $myret + $? ))
                fi
            done
        fi
        # modification des points de montage si besoin (protection du systeme local !)
        zfs list -H -o mountpoint,name -r $ZFSDEST | awk '($1 !~ /^'$(echo $SAVDESTBASE|sed 's@/@\\/@g')'/ && $1 !~ /(legacy|none)/) { gsub("^/$","",$1); printf("zfs set mountpoint='$DESTDIR'%s %s; zfs set orig:mountpoint=%s;\n",$1,$2,$1); }' > $TRACES/$NAME.corrections_montages.sh 2>> $TRACES/$NAME.corrections_montages.log
        if [ -s $TRACES/$NAME.corrections_montages.sh ]; then
            shellex $TRACES/$NAME.corrections_montages.sh >> $TRACES/$NAME.corrections_montages.log 2>&1 
            myret=$?
            [ $myret -eq 0 ] || MOUNTPROBLEM="YES"
            warn_admin $myret "FULLZFS:correction_montages" "$TRACES/$NAME.corrections_montages.sh" "Certains points de montages dangereux ${MOUNTPROBLEM:-non} corriges ${MOUNTPROBLEM:-\!}"
        fi
        # remontage dans l'ordre si / a un mountpoint 'legacy' (monte par fstab) ou autre
        if [ ! -z "$ZFSSLASH" -a -z "$MOUNTPROBLEM" ]; then
            syslogue "info" "($NAME) FULLZFS: remontage dans l'ordre (racine en ZFS)"
            zfs list -H -o canmount,mountpoint,name,mounted -S name -r $ZFSDEST | awk '($1 ~ /^on$/ && $2 !~ /^legacy$/ && $4 ~ /^yes$/) { print $3 }' | xargs -L1 zfs umount
            mount | grep '^'$ZFSDEST'.* on '$DESTDIR | awk '{print $1}' | sort -r | xargs -L1 umount -f || mount -tzfs | grep '^'$ZFSDEST'.* on '$DESTDIR
            mount -tzfs $ZFSDEST/${ZFSSLASH#*/} $DESTDIR
            zfs list -H -o canmount,mountpoint,name -r $ZFSDEST | awk '($1 ~ /^on$/ && $2 !~ /^legacy$/ && $2 ~ /'$(echo $DESTDIR|sed 's@/@\\/@g')'/) { print $3 }' | xargs -L1 zfs mount
        fi

    # AUTRES/MIXED FS SCENARIO
    else
        allret=0
        for fsdesc in $FSLIST; do
            dir=${fsdesc#*:}
            fst=${fsdesc%:*}
            if ! is_excluded $dir; then
                #echo -n " $dir"
                case $fst in
                # UFS: ca peut faire des snapshots, mais pas beaucoup
                #   on en fait un pour le rsync, puis on le detruit
                ufs)
                    get_ufs $dir
                    myret=$(( $myret + $? ))
                ;;
                # ZFS a son script qui fait tout ca tres bien (snapshot a la source)
                zfs)
                    get_zfs $dir
                    myret=$(( $myret + $? ))
                ;;
                # ext[234], autres: un simple rsync + snapshot
                *)
                    get_fs $dir
                    myret=$(( $myret + $? ))
                ;;
                esac
            else
#               echo "$dir EXCLU"
            fi
	    if [ $myret -ne 0 ]; then
              allret=$(( $allret + $myret ))
            fi
        done
        echo "LASTSAV=\"$(env TZ=UTC date)\"" >> $srvinfos
        if [ $allret -eq 0 ]; then
          syslogue "info" "($NAME) done :)"
        else
          syslogue "notice" "($NAME) done with warnings :-/"
        fi
    fi
    cleanup_srv
    exit $allret
else
    plainte "Pas de sauvegarde pour $NAME cette fois :-("
    exit 2
fi
