#!/bin/sh
#
# SCRIPT TEMPLATE - ALL UNIX OS
#
if [ -z "$CONFIG_LOADED" ]; then
  echo "ne pas utiliser directement"
  echo " utiliser $mydir/savscript.sh machine"
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
#RSYNC_DIRECT=${RSYNC_DIRECT:-"YES"}
RSYNC_DIRECT="NO"
SAV_JAILS=${SAV_JAILS:-NO}
SAV_DOWN_JAILS=${SAV_DOWN_JAILS:-NO}
SAV_PROXMOX=${SAV_PROXMOX:-NO}
CANSKIP=${CANSKIP:-0}

. $mydir/lib/savscript.inc.sh

DEST=${DEST:-$NAME}

echo -- $ZRECURSION | grep -q r && SNAP_AFTER=YES

justdoit() {
  if [ ! -z "$JUSTSAYIT" ]; then
    echo "$@" >&2
  else
    eval $@
  fi
}

if init_srv $DEST; then
    syslogue "info" "($NAME): start"

    syslogue "debug" "($NAME): ZPOOLS=$ZPOOLS"
    if [ ! -z "$ZPOOLS" ]; then
        for pool in $ZPOOLS; do
            justdoit zfs_presnap $pool
        done
    fi

    myret=0

    # JAILS
    if [ "$SAV_DOWN_JAILS" = "YES" ] && [ -n "$INACTIVEJAILS" ]; then
        JAILS="$JAILS $INACTIVEJAILS"
    fi
    if [ "$SAV_JAILS" = "YES" ]; then
        if [ ! -z "$JAILS" ]; then
            # get cloned origins
            if [ ! -z "$IORIGIN" ]; then
                ZR="$ZRECURSION"
                ZRECURSION="-R"
                for o in $IORIGIN; do
                    syslogue "debug" "($NAME): get iocage origin $o"
                    get_zfs $(get_srcdir_for_zfs $o) $JAILSZFSDEST/${NAME}_${o##*/} $o
                done
                ZRECURSION="$ZR"
            fi
            for jaildir in $JAILS; do
                if ! is_excluded $jaildir; then
                    justdoit get_jail $jaildir
                    myret=$(( $ret + $? ))
                fi
            done
        fi
	if [ ! -z "$IOJAILS" ]; then
		now_exclude /iocage/jails
	fi
	now_exclude ${IORIGIN%%/releases*}/releases
	now_exclude ${IORIGIN%%/releases*}/download
    fi

    # PROXMOX part
    if [ "$SAV_PROXMOX" = "YES" ] && [ -n "$PVECLUSTER" ]; then
        PVEZFSDEST="${SAVZFSBASE}/$PVECLUSTER"
        PVEDESTDIR="$(zfs list -Homountpoint $PVEZFSDEST 2>/dev/null || ( zfs create $PVEZFSDEST && zfs list -Homountpoint $PVEZFSDEST ) )"
        for lxc in $(echo "$PVELXCS"); do
            syslogue "debug" "($NAME) get PVE LXC $lxc"
            get_proxmox_lxc $lxc
            [ "$SNAP_AFTER" = "YES" ] && justdoit snapshot_dest $PVEZFSDEST/$lxc
        done
        for qemu in $(echo "$PVEQMS"); do
            syslogue "debug" "($NAME) get PVE QEMU $qemu"
            get_proxmox_qemu $qemu
            [ "$SNAP_AFTER" = "YES" ] && justdoit snapshot_dest $PVEZFSDEST/$qemu
        done
        for storage in $(echo "$PVESTORAGES" | grep ' [^$]'); do
            syslogue "debug" "($NAME) now exclude ${storage#*|}"
            now_exclude ${storage#* }
        done
    fi

    # FULL ZFS SCENARIO
    if [ "$FULLZFS" = "YES" ]; then
        # tout est en ZFS: cool :)
        for testfs in $ZFSLIST; do
            zfsanddir=${testfs%%|*}
            is_excluded ${zfsanddir#*|} && now_exclude ${zfsanddir%|*}
        done 
        # si aucune exclusion + c'est le seul zpool, alors on lance en un coup
        #export DONOTEXCLUDEZFS="for now"
        if [ -n "$ONEZPOOL" ]; then
            syslogue "info" "($NAME) ONEFULLZFS: sauvegarde du pool ZFS $ONEZPOOL"
            justdoit get_zfs / $ZFSDEST $ONEZPOOL
            myret=$(( $myret + $? ))
        else
            # si la racine est en ZFS, le pool ZFS vient a la racine
            if [ -n "$ZFSSLASH" ]; then
                syslogue "debug" "($NAME) ZFSSLASH: get ${ZFSSLASH%%/*}"
                justdoit get_zfs / $ZFSDEST ${ZFSSLASH%%/*}
                now_exclude_zfs_only ${ZFSSLASH%%/*}
            fi
            for fs in $ZFSLIST; do
                zfsanddir=${fs%|*}
                zfsopts=${fs#${zfsanddir}|}
                if ! is_excluded ${zfsanddir%|*} && ! is_excluded ${zfsanddir#*|} && [ "${zfsanddir#*|}" != "none" ] && [ "${zfsopts%/*}" = "yes" ]; then
                    origzfs=${zfsanddir%|*}
                    syslogue "debug" "($NAME) zfs loop: $origzfs"
                    justdoit get_zfs ${zfsanddir#*|} ${ZFSDEST}${zfsanddir#*|} ${origzfs}
                    myret=$(( $myret + $? ))
                fi
            done

        fi
	# corrige une racine ZFS freebsd (zroot/ROOT/default => /)
	if [ -n "$ZFSSLASH" ]; then
            if [ "$(zfs get -H -o value canmount $ZFSDEST)" = "on" ]; then
              [ "$(zfs get -H -o value mountpoint $ZFSDEST)" = "none" ] || zfs set mountpoint=none $ZFSDEST
            fi

	    if [ "$(zfs get -H -o value mountpoint $ZFSDEST/${ZFSSLASH#*/})" != "$DESTDIR" ]; then
                zfs set mountpoint=$DESTDIR $ZFSDEST/${ZFSSLASH#*/}
                if [ "$(zfs get -H -o value canmount $ZFSDEST/${ZFSSLASH#*/})" = "noauto" ]; then
                    zfs set orig:canmount=noauto $ZFSDEST/${ZFSSLASH#*/}
                    zfs set canmount=on $ZFSDEST/${ZFSSLASH#*/}
                    [ "$(zfs get -H -o value mounted $ZFSDEST/${ZFSSLASH#*/})" = "yes" ] || zfs mount $ZFSDEST/${ZFSSLASH#*/}
                fi
            fi
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
                    justdoit get_ufs $dir $DESTDIR/${dir#/} $ZFSDEST${dir%/}
                    myret=$(( $myret + $? ))
                ;;
                # ZFS a son script qui fait tout ca tres bien (snapshot a la source)
                zfs)
                    if [ "$dir" = "/" ]; then
                        [ -z "$ZFSSLASH" ] && syslogue "warning" "ZFS / but \$ZFSSLASH empty ??? skipping" && continue
                        justdoit get_zfs $dir $ZFSDEST $ZFSSLASH
                    else
                        justdoit get_zfs $dir $ZFSDEST/${dir#/} $(get_zfs_src_for $dir)
                    fi
                    myret=$(( $myret + $? ))
                ;;
                # ext[234], autres: un simple rsync + snapshot
                *)
                    justdoit get_fs $dir $DESTDIR/${dir#/} $ZFSDEST${dir%/}
                    myret=$(( $myret + $? ))
                ;;
                esac
#            else
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
    # modification des points de montage si besoin (protection du systeme local !)
    zfs list -H -o mountpoint,name,jailed -r $ZFSDEST | awk '($1 !~ /^'$(echo $DESTDIR|sed 's@/@\\/@g')'/ && $1 ~ /^\// && $3 ~ /off/) { rel=$1; gsub("^/$","",rel); printf("zfs set mountpoint='$DESTDIR'%s %s; zfs set orig:mountpoint=%s %s;\n",rel,$2,$1,$2); }' > $TRACES/$NAME.corrections_montages.sh 2>> $TRACES/$NAME.corrections_montages.log
    if [ -s $TRACES/$NAME.corrections_montages.sh ]; then
        justdoit shellex $TRACES/$NAME.corrections_montages.sh >> $TRACES/$NAME.corrections_montages.log 2>&1
        myret=$?
        myret=$(($myret + $(grep -v '^+' $TRACES/$NAME.corrections_montages.log | wc -l)))
        [ $myret -eq 0 ] || MOUNTPROBLEM="YES"
        warn_admin $myret "FULLZFS:correction_montages" "$TRACES/$NAME.corrections_montages.sh" "Certains points de montages dangereux ${MOUNTPROBLEM:+non }corriges ${MOUNTPROBLEM:+\!}"
    fi
    # remontage dans l'ordre si / a un mountpoint 'legacy' (monte par fstab) ou canmount=noauto (nouvelle methode)
    if [ -n "$ZFSSLASH" ] && [ -z "$MOUNTPROBLEM" ]; then
        syslogue "info" "($NAME) FULLZFS: remontage dans l'ordre (racine en ZFS)"
        zfs list -H -o canmount,mountpoint,name,mounted -S name -r $ZFSDEST | awk '($1 ~ /^on$/ && $2 ~ /^\// && $4 ~ /^yes$/) { print $3 }' | xargs -L1 zfs umount
        mount | grep '^'$ZFSDEST'.* on '$DESTDIR | awk '{print $1}' | sort -r | xargs -L1 umount -f || mount -tzfs | grep '^'$ZFSDEST'.* on '$DESTDIR
        mount -tzfs $ZFSDEST/${ZFSSLASH#*/} $DESTDIR
        zfs list -H -o canmount,jailed,mountpoint,name -r $ZFSDEST | awk '($1 ~ /^on$/ && $2 !~ /^on$/ && $3 ~ /^\// && $3 ~ /'$(echo $DESTDIR|sed 's@/@\\/@g')'/) { print $4 }' | while read z; do
            mount | grep -q "^$z " || zfs mount $z
        done
    fi

    [ "$SNAP_AFTER" = "YES" ] && justdoit snapshot_dest $ZFSDEST
    justdoit cleanup_srv
    exit $allret
else
    if [ $CANSKIP -eq 0 ]; then
        syslogue "error" "Pas de sauvegarde pour $NAME cette fois :-("
        exit 2
    fi
fi
