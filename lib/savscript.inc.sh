#!/bin/sh
#
# include pour chaque script serveur
#
# utilise les variables "$NAME","$DEST","$excludes"
#. /usr/local/admin/utils/common/common.sh.inc
. $mydir/lib/log.inc.sh

#ZFS_SYNC_VOL=${ZFS_SYNC_VOL:-$(which zfs_sync_vol)}
#ZFS_SNAP_MAKE=${ZFS_SNAP_MAKE:-$(which zfs_snap_make)}
excludefrom=$TRACES/$NAME.excludes
ZEXCLUDES="-x $excludefrom.zfs"
#ZOPTS="-k $SSH_KEY -C -m 'GMT-%Y.%m.%d-%H.%M.%S' -I"
ZOPTS="-k $SSH_KEY -Cup"
ZRECURSION="-r"

if [ $DEBUG -ge 4 ]; then
    ZOPTS=$ZOPTS" -vv"
    doit() {
        syslogue "debug" "($NAME) DID NOT(DEBUG): $*"
        return 0
    }
    shellex() {
        doit /bin/sh -x $@
    }
elif [ $DEBUG -ge 1 ]; then
    ZOPTS=$ZOPTS" -v"
    [ $DEBUG -ge 3 ] && ZOPTS=$ZOPTS" -v"
    doit() {
        syslogue "debug" "($NAME) DEBUG: $*"
        $@
    }
    shellex() {
        if [ $DEBUG -ge 3 ]; then
          doit /bin/sh -x $@
        else
          doit /bin/sh $@
        fi
    }
else
    doit() {
        syslogue "debug" "($NAME): $*"
        $@
    }
    shellex() {
        /bin/sh $@
    }
fi

if [ ! -z "$SYSLOG_FACILITY" ]; then
    ZOPTS=$ZOPTS" -l $SYSLOG_FACILITY"
fi
# use: rsync_it srcdir/ dstdir/ logfile
rsync_it() {
    [ $DEBUG -ge 2 ] && RSYNC_OPTS=$RSYNC_OPTS" -vv"
    doit $RSYNC_COMMAND $RSYNC_OPTS $(rsync_excludes_for ${1}) ${RSYNC_SRV_BASE}${1} ${2} >> ${3} 2>&1
    res=$?
    case $res in
        0|23|24)
            return 0
        ;;
        *)
            err="OUI"
        ;;
    esac
    return $res
}

# teste si un chemin est a exclure
is_excluded() {
    local testsrc=$1
    case "$testsrc" in
      /*)
        [ -s "$excludefrom" ] || return 1
        while [ -n "$testsrc" ]; do
          grep -q "^${testsrc}$" $excludefrom 2>/dev/null && return 0
          testsrc=${testsrc%/*}
        done
        ;;
      *)
        [ -s "$excludefrom.zfs" ] || return 1
        while [ -n "$testsrc" ] && [ "$testsrc" != "${otestsrc:-nadaquedalle}" ]; do
          grep -q "^${testsrc%/}$" $excludefrom.zfs 2>/dev/null && return 0
          otestsrc=$testsrc
          testsrc=${testsrc%/*}
        done
        ;;
    esac
    return 1
}

# construit une liste d'exclusions pour rsync
rsync_excludes_for() {
    test -s "$excludefrom" || return 1
    for x in $(cat $excludefrom); do
        case $x in
        /)
            syslogue "error" "excluding / ?"
            tmpargs=$tmpargs"--exclude \"/\""
        ;;
        /*)
            expr "$x" : "$(echo $1 | sed 's@/@\\/@g; s@\.@\\.@g;')" >/dev/null && tmpargs=$tmpargs"--exclude \"${x#$1}\" "
        ;;
        *)
            is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
            tmpargs=$tmpargs"--exclude \"$test\" "
        ;;
        esac
    done
    echo "$tmpargs"
}

# exclus un chemin de la suite
now_exclude() {
    for arg in $*; do
      is_excluded "$arg" && return 0
      case "$arg" in
        /*)
          syslogue "debug" "now_exclude($arg): path"
          echo "$arg" >> $excludefrom
          if [ -n "$ZFSLIST" ]; then
              for zfsdesc in $ZFSLIST; do
                  local zfsmntpoint="${zfsdesc%|*}"
                  zfsmntpoint=${zfsmntpoint#*|}
                  if [ "${zfsmntpoint}" = "$arg" ]; then
                      is_excluded "${zfsdesc%%|*}" || echo "${zfsdesc%%|*}" >> $excludefrom.zfs
                  fi
              done
          fi
          ;;
        *)
          syslogue "debug" "now_exclude($arg): ZFS"
          if [ -n "$ZFSLIST" ]; then
            for zfsdesc in $ZFSLIST; do
              if [ "${zfsdesc%%|*}" = "$arg" ]; then
                echo ${arg} >> $excludefrom.zfs
                local srcdir_for=$(get_srcdir_for_zfs ${arg})
                echo "${zfsdesc%|*}" | grep -q "^[^\|]*|/..*|" || continue
                is_excluded "${srcdir_for}" ||  echo "${srcdir_for}" >> $excludefrom
                return 0
              fi
            done
          fi
          ;;
      esac
    done
}

now_exclude_zfs_only() {
    for arg in $*; do
        is_excluded "$arg" && return 0
        echo ${arg} >> $excludefrom.zfs
    done
}

# warn_admin retcode "object" "tracefile" "message"
warn_admin() {
    wcode=$1
    subject=$2
    [ -s $3 ] && PROBLEMFILES=$PROBLEMFILES" "$3
    wmsg=$4
    [ $wcode -eq 0 ] && msg="ok but \"$4\"" || msg="return $wcode ($4)"
    echo "${NAME}: $2 $msg "${3:+"- see $3"} >> $TRACES/msg
    [ $wcode -gt 0 ] && syslogue "error" "($NAME): $2 $msg ${3:+- see $3}"
}

say_begin() {
    T=$(date +%s)
    echo -n "$*"
}

say_end_with() {
    [ ! -z "$NOTIME" ] && return $1
    TT=$(( $(date +%s) - $T ))
    code=$1
    shift
    if [ $code -eq 0 ]; then
      echo -n " ${TT}s :-) "
    else
      echo -n " ${TT}s :-/ "
    fi
    if [ $# -gt 0 ]; then
      echo -n "$*"
    fi
    return $code
}

debug() {
  [ $DEBUG -gt 0 ] && echo $@ 1>&2
}

snapshot_dest() {
  syslogue "debug" "snapshot_dest($*)"
  V=$1
  SNAPNAME=${SNAPNAME:-$(TZ=GMT date +GMT-%Y.%m.%d-%H.%M.%S)}
  doit /sbin/zfs snapshot -r $V@$SNAPNAME
  keep=0
  for s in $(zfs list -H -o name -r -t snapshot -S creation -d1 $V | grep @GMT-); do
    keep=$(( $keep + 1 ))
    if [ $keep -gt 150 ]; then
      syslogue "notice" "snapshot_dest($*): destroy $s ($keep)"
      zfs destroy -r $s
    fi
  done
}

zfs_mount_recurse() {
  syslogue "debug" "mount_recurse($1)"
  for z in $(zfs list -H -o canmount,jailed,mountpoint,name -r $1 | awk '($1 ~ /^on$/ && $2 !~ /^on$/ && $3 ~ /^\// && $3 ~ /'$(echo $DESTDIR|sed 's@/@\\/@g')'/) { print $4 }'); do
      doit "mount | grep -q "^$z " || zfs mount $z"
  done
}

##############
### Source ###
##############
srvinfos=$DESTDIR.infos

# init_srv()
#
# contacte la machine et recupere quelques infos:
# - SYSTEM (uname -s)
# - SYSVER (uname -r)
# - FSLIST (liste de fstype:/montage)
# - RSYNC_SRV_PID si un demon rsync a pu etre lance sur $RSYNC_PORT
# - ZFSLIST (zfs filesystems)
# - ZPOOLS (pools zfs)
# - ZFSSLASH (racine ZFS si 'legacy')
# si FreeBSD:
#   - JAILS (liste de repertoires)
# si Linux/Proxmox:
#   - PVESTORAGES (liste des storages *locaux*)
#   - PVELXCS (liste des containers LXC avec leurs disques)
#   - PVEQMS (liste des vm's qemu avec leurs disques)
init_srv() {
    if fping -q $DEST; then
        test -f $srvinfos && mv $srvinfos $srvinfos.last
        $REMOTE_COMMAND $DEST "SYSTEM=\$(uname -s);
SYSVER=\$(uname -r)
[ \"\$SYSTEM\" = \"FreeBSD\" ] && SEDOPT=-E || SEDOPT=-r
echo \"SYSTEM=\$SYSTEM\";
echo \"SYSVER=\$SYSVER\";
echo \"FSLIST=\\\"\$(mount -t $FSTYPES | sed \$SEDOPT 's@^.*on (/[^ ]*) (\(|type )([a-zA-Z0-9]+).*\$@\3:\1@' | sort -t: -k2)\\\"\";
if [ \"\$(uname -s)\" = \"FreeBSD\" -a \${SYSVER%%.*} -gt 6 ]; then
  echo JAILS=\\\"\$(/usr/sbin/jls | awk '(\$1 ~ /^[0-9]+\$/) { printf(\"%s\\\n\",\$NF); }')\\\";
  if [ -x /usr/local/bin/ezjail-admin ]; then
    echo INACTIVEJAILS=\\\"\$(cd /usr/local/etc/ezjail; ls | fgrep norun | xargs -L1 awk 'BEGIN { FS=\"\\\"\" } (\$1 ~ /rootdir/) { print \$2 }')\\\";
  fi
  if [ -x /usr/local/bin/iocage ]; then
    echo INACTIVEJAILS=\\\"\$(/usr/local/bin/iocage list -hl | awk '((\$4 == \"down\")&&(\$2 != \"basejail\")) { printf(\"/iocage/jails/%s/root\\\n\",\$2);}')\\\";
    echo IOJAILS=\\\"\$(/usr/local/bin/iocage list -hl | awk '(\$4 == \"up\") { printf(\"/iocage/jails/%s/root\\\n\",\$2);}')\\\";
    echo IORIGIN=\\\"\$(zfs list -H -o origin -d 2 -r /iocage/jails|grep -v ^- | sed 's/@.*$//; s/\/root$//;' | sort -u )\\\";
  fi
fi
if [ \$(mount -t zfs | wc -l) -gt 0 ]; then
  echo ZPOOLS=\\\"\$(/sbin/zpool list -H -o name)\\\";
  echo ZFSSLASH=\\\"\$(zfs list -H -omountpoint,name / | awk '{print \$2}')\\\";
  echo ZFSLIST=\\\"\$(zfs list -H -oname,mountpoint,mounted,canmount | awk '{printf(\"%s|%s|%s/%s\\\n\",\$1,\$2,\$3,\$4);}')\\\";
fi
if [ \"\$(uname -s)\" = \"Linux\" ] && [ -e \"/etc/pve/local\" ]; then
  echo PVECLUSTER=\\\"\$(pvecm status|grep ^Name: | awk '{print \$NF}')\\\"
  echo PVESTORAGES=\\\"\$(pvesm status --content images | awk '{if(\$3==\"active\"){print \$1}}' | while read s; do pvesh get /storage/\$s --noborder --noheader | awk 'BEGIN{want=0;zpool=\"\";dpath=\"\"}/^pool/{zpool=\$2;}/^shared.*1$/{want=0;}/^(path|mountpoint)/{dpath=\$2; want=1;}END{if(want==1){printf(\"'\$s':%s %s\\\n\",dpath,zpool)}}'; done)\\\";
  if [ -x /usr/sbin/pct ]; then
    echo PVELXCS=\\\"\$(pct list | grep ' running *[^$]' | awk '{if(\$2==\"running\"){print \$1}}')\\\";
  fi
  if [ -x /usr/sbin/qm ]; then
    echo PVEQMS=\\\"\$(qm list | grep ' running *[0-9]' | awk '{ print \$1 }')\\\";
  fi
fi" > $srvinfos 2> $TRACES/$NAME.init_srv
        . $srvinfos >> $TRACES/$NAME.init_srv 2>&1
    else
        if [ ${CANSKIP:-0} -eq 0 ]; then
            syslogue "crit" "Serveur $DEST down. Pas de sauvegarde"
            return 1
        else
            syslogue "info" "Serveur $DEST down. Pas de sauvegarde (CANSKIP)"
            return 1
        fi
    fi
    ### on a les infos du serveur: on les digere
    if [ "$SYSTEM" = "FreeBSD" ]; then
        #on cree le fichier d'exclusions pour zfs
        test -f $excludefrom.zfs && rm $excludefrom.zfs
        test -f $excludefrom && rm $excludefrom
        # si jails inactifs, on les exclue
        if [ ! -z "$INACTIVEJAILS" ]; then
            now_exclude $(echo $INACTIVEJAILS)
        fi
        # transfere les exclusions dans les fichiers d'exclusion
        if [ ! -z "${EXCLUDES:-$DEFAULT_EXCLUDES}" ]; then
            for e in $(echo ${EXCLUDES:-$DEFAULT_EXCLUDES}); do
                now_exclude "$e"
            done
        fi
        for fsdesc in $FSLIST; do
            case ${fsdesc} in
                zfs:*) ZFS=YES ;;
                ufs:*) UFS=YES ;;
                *) OTHERFS=YES ;;
            esac
        done
        # si ZFS a la source
        if [ ! -z "$ZFSLIST" ]; then
            if [ ! -x "$ZFS_SYNC_VOL" ]; then
                warn_admin 1 "init_srv($*)" "" "Impossible de trouver zfs_sync_vol dans $PATH \!"
                return 1
            fi
            # si ZFS only: pas besoin de demon rsync
            if [ -n "$ZFS" ] && [ -z "$UFS$OTHERFS" ]; then
                FULLZFS=YES
                # si un seul zpool, c'est encore plus clair
                if [ $(expr "$ZPOOLS" : ".* ") -eq 0 ]; then
                    ONEZPOOL=$ZPOOLS
                else
                # ... ou si un seul non-exclu
                    npools=0
                    pools=""
                    for pool in $ZPOOLS; do
                        if ! is_excluded $pool; then
                            npools=$(( npools+1 ))
                            pools="$pools $pool"
                        fi
                    done
                    if [ $npools -eq 1 ]; then
                        # on oublie simplement les autres pools s'ils sont exclus
                        ONEZPOOL=${pools# }
                        ZPOOLS=${pools# }
                    fi
                fi
                echo "ONEZPOOL=$ONEZPOOL" >> $srvinfos
                echo "ZPOOLS=\"$ZPOOLS\"" >> $srvinfos
                echo "FULLZFS=$FULLZFS" >> $srvinfos
            fi
        fi
    fi

    if [ ! -z "$SYSVER" -a ! -z "$FSLIST" ]; then
        trap cleanup_srv 2 3
    else
        warn_admin 1 "init_srv($*)" "$TRACES/$NAME.init_srv" "Impossible d'initialiser la sauvegarde"
        return 1
    fi

    if [ -z "$FULLZFS" ]; then
        get_rsync_daemon
        if [ ! -z "$RSYNC_SRV_PID" ] && $RSYNC --port=$RSYNC_PORT ${DEST}:: >> $TRACES/$NAME.get_rsync_daemon 2>&1 ; then
            export RSYNC_COMMAND="$RSYNC --port=$RSYNC_PORT"
            RSYNC_SRV_BASE="${DEST}::root"
        else
            RSYNC_SRV_BASE="${DEST}:"
            export RSYNC_RSH="$REMOTE_COMMAND"
            export RSYNC_COMMAND="$RSYNC"
        fi
    fi

    return 0
}

get_rsync_daemon() {
    if [ "$RSYNC_DIRECT" = "YES" ]; then
        eval $($REMOTE_COMMAND $DEST "RSYNC_SRV_DIR=/tmp/SAV.rsyncd;
MYADDR=\$(echo \${SSH_CONNECTION} | awk '{print \$3}');
if [ -d \$RSYNC_SRV_DIR ]; then
  test -s \$RSYNC_SRV_DIR/rsyncd.pid && kill \$(cat \$RSYNC_SRV_DIR/rsyncd.pid) > /dev/null 2>&1;
  rm -rf \$RSYNC_SRV_DIR;
  pgrep -qf 'rsync.*/tmp/SAV' && pkill -9 -f 'rsync.*/tmp/SAV';
fi;
if mkdir \$RSYNC_SRV_DIR; then
  cat > \$RSYNC_SRV_DIR/rsyncd.conf << EOF
uid = root
gid = 0
use chroot = no
max connections = 4
syslog facility = daemon
address = \$MYADDR
port = $RSYNC_PORT
pid file = \$RSYNC_SRV_DIR/rsyncd.pid
log file = \$RSYNC_SRV_DIR/rsyncd.log
[root]
    path = /
    hosts allow = \${SSH_CLIENT%% *}
    read only = true
EOF
  if rsync --daemon --config=\$RSYNC_SRV_DIR/rsyncd.conf < /dev/null; then
    sleep 1;
    echo RSYNC_SRV_PID=\$(cat \$RSYNC_SRV_DIR/rsyncd.pid|grep -v ^$);
    echo RSYNC_VERSION=\$(rsync --version | grep version | awk '{print \$NF}')
  fi;
fi" 2> $TRACES/$NAME.get_rsync_daemon) >> $TRACES/$NAME.get_rsync_daemon 2>&1
        if [ ! -z "$RSYNC_SRV_PID" ]; then
            RSYNC_SRV_BASE="${DEST}::root"
            return 0
        fi
    fi
    echo "RSYNC_DIRECT=$RSYNC_DIRECT" >> $TRACES/$NAME.get_rsync_daemon
    echo "RSYNC_SRV_PID=$RSYNC_SRV_PID" >> $TRACES/$NAME.get_rsync_daemon
    return 1;
}

cleanup_srv() {
    if [ ! -z "$RSYNC_SRV_PID" ]; then
        CLEANUP_COMMAND="test -f /tmp/SAV.rsyncd/rsyncd.log && cat /tmp/SAV.rsyncd/rsyncd.log; kill \$(cat /tmp/SAV.rsyncd/rsyncd.pid); rm -rf /tmp/SAV.rsyncd;"
        unset RSYNC_SRV_PID
    fi
    if [ ! -z "$ZFS_PRESNAPS" ]; then
        for p in $ZFS_PRESNAPS; do
            CLEANUP_COMMAND=$CLEANUP_COMMAND" zfs destroy -d -r $p;"
        done
    fi
    if [ ! -z "$CLEANUP_COMMAND" ]; then
        $REMOTE_COMMAND $DEST "$CLEANUP_COMMAND" >> $TRACES/$NAME.cleanup_srv 2>&1
        myres=$?
        if [ $myres -ne 0 ]; then
            warn_admin $myres "cleanup_srv" "$TRACES/$NAME.cleanup_srv" "running \"$CLEANUP_COMMAND\""
        else
            unset CLEANUP_COMMAND
        fi
        return $myres
    fi
    # supprime les snapshots de transfert d'une autre source vers le serveur sauvegardé
    if [ -z "$NEVER_CLEAN_ZFS_SPURIOUS_SNAPS" ]; then
        for snap in $(zfs list -H -oname -r -t snapshot $ZFSDEST | grep '@.*-'$NAME'-2'); do
            syslogue "info" "cleanup_srv(): destroying $snap"
            zfs destroy -d $snap || warn_admin 1 "cleanup_srv(): unable to destroy $snap"
        done
    fi
    return 0
}

#######################
### ZFS destination ###
#######################
is_zfs_path() {
    case "$1" in
    /*) return 1 ;;
    *) return 0 ;;
    esac
    return 1
}

# determine le rep destination pour une source
get_destdir_for() {
    is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
    syslogue "debug" "get_destdir_for($1 - $test) => ?)"
    reltest=${test#/}
    if is_jailed $test; then
        syslogue "debug" "get_destdir_for($1) (jailed) => $JAILSDESTDIR/$curjail${test#$curjaildir}"
        echo $JAILSDESTDIR/$curjail${test#$curjaildir}
    else
        syslogue "debug" "get_destdir_for($1) => $DESTDIR${reltest:+/}${reltest%/}"
        echo $DESTDIR${reltest:+/}${reltest%/}
    fi
}

# determine la destination ZFS
get_zfsdest_for() {
    is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
    syslogue "debug" "get_zfsdest_for($1 - $test) => ?)"
    reltest=${test#/}
    if is_jailed $test; then
        echo $JAILSZFSDEST/$curjail${test#$curjaildir}
        syslogue "debug" "get_zfsdest_for($1) => $JAILSZFSDEST / $curjail ${test#$curjaildir/}"
    else
        echo $ZFSDEST${reltest:+/}${reltest%/}
        syslogue "debug" "get_zfsdest_for($1) => $ZFSDEST${reltest:+/}${reltest%/}"
    fi
}

# renvoie le chemin ZFS de la source pour un repertoire
get_zfs_src_for() {
    syslogue "debug" "get_zfs_src_for($1) => ?)"
    for zfsdesc in $ZFSLIST; do
        zfsanddir=${zfsdesc%|*}
        zfsopts=${zfsdesc#${zfsanddir}|}
        if [ "${1}" = "${zfsanddir#*|}" ] && [ "${zfsopts%/*}" = "yes" ]; then
            echo "${zfsdesc%%|*}"
            syslogue "debug" "get_zfs_src_for($1) => ${zfsdesc%%|*})"
            return
        fi
    done
    return 1
}

# renvoie le chemin sur la source pour un volume ZFS source
get_srcdir_for_zfs() {
    syslogue "debug" "get_srcdir_for_zfs($1) => ?)"
    for zfsdesc in $ZFSLIST; do
        zfsanddir=${zfsdesc%|*}
        zfsopts=${zfsdesc#${zfsanddir}|}
        if [ "${1}" = "${zfsanddir%|*}" ] && [ "${zfsopts%/*}" = "yes" ]; then
            echo ${zfsdesc} | cut -d'|' -f2
            syslogue "debug" "get_srcdir_for_zfs($1) => $(echo ${zfsdesc} | cut -d'|' -f2)"
            return
        fi
    done
    return 1
}

# creation d'un volume ZFS si besoin, verification du montage
# usage: init_zfs_dest <srcdir> <dstdir> <zfsdst>
# cree les variable:
#   $mydestdir (rep de sauvegarde pour ce chemin)
#   $myzfsdest (vol zfs correspondant)
init_zfs_dest() {
    [ $# -ne 3 ] && exit 1
    mydir=${1}
    mydestdir=${2}
    myzfsdest=${3}
    # creer le vol zfs dest si besoin et le remplir de ce qu'on avait avant dans le meme repertoire
    if ! zfs list -H -o name $myzfsdest >/dev/null 2>&1; then
        if [ -d $mydestdir ]; then
            doit mv $mydestdir $mydestdir.rsync
            warn_admin 0 "init_zfs_dest($*)" "" "Le repertoire $mydestdir existait et n'etait pas un volume ZFS. Il a ete deplace en $mydestdir.rsync"
        fi

        # en cas de montage d'un zfs dans une arborescence !zfs
        # on cree les elements intermediaires sans montage
        # (l'ordre *doit* etre du plus court au plus long)
        myzpath=$myzfsdest
        ztocreate=""
        while ! zfs list -H -o name ${myzpath%/*}; do
            ztocreate=${myzpath%/*}" "$ztocreate
            myzpath=${myzpath%/*}
        done
        for zc in $ztocreate; do
            doit zfs create -o canmount=off -o orig:mountpoint=none -o orig:canmount=off $zc
        done
        doit zfs create -o orig:mountpoint=$mydir $myzfsdest

    else
        # verifier que la destination est bien montee
        mount | grep -q ^$myzfsdest' ' && doit zfs umount $myzfsdest
        # MAJ orig:mountpoint
        if [ "$(zfs get -H -ovalue orig:mountpoint $myzfsdest)" != "$1" ]; then
            doit zfs set orig:mountpoint=$1 $myzfsdest
        fi
        if [ "$(zfs get -H -o value readonly ${myzfsdest})" != "off" ]; then
            doit zfs set readonly=off $myzfsdest
        fi
        doit zfs mount $myzfsdest
    fi
}

###########################
### Filesystems sources ###
###########################
# generique: rsync 'simple'
# usage: get_fs srcdir dstdir zfsdest
get_fs() {
    [ $# -ne 3 ] && exit 1
    dir=$1
    local mydestdir=$2
    local myzfsdest=$3
    say_begin "$dir"
    init_zfs_dest $dir $mydestdir $myzfsdest
    L=$TRACES/$NAME.get_fs.$(echo $1 | sed 's@/@_@g')
    rsync_it ${dir%/}/ $mydestdir/ $L
    ret=$?
    shellex $ZFS_SNAP_MAKE -q $myzfsdest
    if [ $ret -ne 0 ]; then
        warn_admin $ret "get_fs($*)" $L "Pb avec $RSYNC_COMMAND $RSYNC_DSTBASE${dir}"
    fi
    say_end_with $ret
}

# usage: get_ufs srcdir dstdir zfsdest
get_ufs() {
    [ $# -ne 3 ] && exit 1
    dir=$1
    local mydestdir=$2
    local myzfsdest=$3
    say_begin "UFS:$dir"
    L=$TRACES/$NAME.get_ufs.$(echo $1 | sed 's@/@_@g')
    UFSSNAPNAME=rsync.$(date +%Y%m%d-%H%M%S)
    UFSMOUNTDIR=/tmp/mntsav_$(hostname -s)$(echo ${dir%/}|sed 's@/@_@g')
    # creation du snapshot a la source
    if [ ${SYSVER%%.*} -gt 5 ]; then
        UFSTS=$($REMOTE_COMMAND $DEST "\
            if [ -d \"${dir}\" ] && [ -d ${dir%/}/.snap ]; then \
              if mount -u -o snapshot ${dir%/}/.snap/$UFSSNAPNAME ${dir}; then \
                TS=\$(TZ=UTC date +%s); \
                mkdir -p $UFSMOUNTDIR; \
                if mount -r /dev/\$(mdconfig -a -t vnode -o readonly -f ${dir%/}/.snap/$UFSSNAPNAME) $UFSMOUNTDIR; then \
                  echo \$TS; \
                else \
                  mdconfig -l -v | grep $UFSSNAPNAME | cut -f1 | xargs -L1 mdconfig -d -u ; \
                  rm -f ${dir%/}/.snap/$UFSSNAPNAME 2>/dev/null; \
                fi; \
              else \
                test -f ${dir%/}/.snap/$UFSSNAPNAME && rm -f ${dir%/}/.snap/$UFSSNAPNAME; \
              fi; \
            fi" 2>>$L ) >> $L
    fi
    init_zfs_dest $dir $mydestdir $myzfsdest
    if [ ! -z "$UFSTS" ]; then
        rsync_it ${UFSMOUNTDIR}/ $mydestdir/ $L
        ret=$?
        # menage du snapshot source
        $REMOTE_COMMAND $DEST "umount $UFSMOUNTDIR || ( fuser -k -m $UFSMOUNTDIR ; umount -f $UFSMOUNTDIR ); \
            mdconfig -l -v | fgrep ${dir%/}/.snap/$UFSSNAPNAME | cut -f1 | xargs -L1 mdconfig -d -u && rm -f ${dir%/}/.snap/$UFSSNAPNAME && rmdir $UFSMOUNTDIR;" || syslogue "error" "AIIIE: snapshot impossible a supprimer: ${dir%/}/$UFSSNAPNAME monte sur $UFSMOUNTDIR" >> $L 2>&1
    else
        [ ${SYSVER%%.*} -gt 5 ] && syslogue "notice" "get_ufs(${dir}@${DEST}): pas reussi a utiliser un snapshot :-/"
        rsync_it ${dir%/}/ $mydestdir/ $L
        ret=$?
    fi
    shellex $ZFS_SNAP_MAKE -q ${UFSTS:+-s $UFSTS} $myzfsdest
    if [ $ret -ne 0 ]; then
        syslogue "error" "Probleme a la sauvegarde de ${DEST}:${dir} (UFS+snapshot)"
        warn_admin $ret "get_ufs($*)" $L "Pb avec $RSYNC_COMMAND$RSYNC_DSTBASE$UFSMOUNTDIR"
    fi
    say_end_with $ret
}

# usage: get_zfs srcdir dstvol srcvol
get_zfs() {
    [ $# -ne 3 ] && return 1
    if [ "$1" = "legacy" ]; then
        return
    fi
    local ret=0
#    echo "get_zfs $*" >> /tmp/$(echo "$DEST $*" | sed 's/[^-a-zA-Z0-9]/_/g')
    ztarget=$1
    d=${2}
    if [ ! -z "$d" ]; then
        if ! [ -n "$(zfs list -H -oname ${d%/*})" ]; then
            syslogue "debug" "get_zfs($1): missing parent zfs ${d%/*}"
            miss="${d%/*}"
            sd="${d%/*}"
            while ! zfs list -Honame ${sd%/*} > /dev/null 2>&1; do
                miss=${sd%/*}" "${miss}
                sd="${sd%/*}"
            done
            for emptyzfs in ${miss}; do
                syslogue "debug" "get_zfs($1): create parent zfs ${emptyzfs}"
                if ! doit zfs create -o canmount=off ${emptyzfs} 2>/dev/null; then
                    syslogue "info" "get_zfs(${1}): unable to create ${emptyzfs}"
                    return 1
                fi
            done
        fi
        # we may transfer a whole zpool with ROOT/default / ?
        if [ "$ztarget" = "/" ] && echo "$d" | fgrep -q "/ROOT/[^/]"; then
            syslogue "debug" "ROOT/* / zfs"
            d=$ZFSDEST
            if ! zfs list -H -oname ${d} > /dev/null 2>&1; then
                if ! doit zfs create -o canmount=off ${d}; then
                    syslogue "info" "get_zfs(${1}): unable to create ${d%/*}"
                    return 1
                fi
            fi
        fi
    fi
    s=${3}
    dm=$(get_destdir_for $ztarget)
    if is_excluded $s; then
      debug "$s excluded"
      return 0
    fi
    L=$TRACES/$NAME.get_zfs.$(echo $1 | sed 's@/@_@g')
    syslogue "debug" "($NAME) get_zfs($@): src=$s dst=$d"
    if [ -z "$d" -o -z "$s" ]; then
        warn_admin 1 "get_zfs($*)" "" "get_zfs($1): impossible de trouver la destination($d) ou la source ZFS ($s)"
        return 1
    fi
    say_begin "ZFS:$ztarget"
    [ $DEBUG -gt 0 ] && echo "DEBUG: shellex $ZFS_SYNC_VOL $ZRECURSION $ZEXCLUDES $ZOPTS ${s}@${DEST} ${d}"
    shellex $ZFS_SYNC_VOL $ZRECURSION $ZEXCLUDES $ZOPTS ${s}@${DEST} ${d} >> $L 2>&1
    ret=$?
    if [ $ret -ne 0 ]; then
        MYZOPTS="-j"
        descpb="inconnu"
        case $ret in
            7) # pb snapshots desynchro
                MYZOPTS=$ZOPTS" -Bj"
                syslogue "warning" "get_zfs(${s}@${DEST}): Deuxieme tentative avec -Bj"
                descpb="snapshots desynchro"
            ;;
            [56]) # volume impossible a creer
                MYZOPTS=$ZOPTS" -c $dm"
                syslogue "warning" "get_zfs(${s}@${DEST}): Deuxieme tentative avec -c $dm"
                descpb="$ZFS_SYNC_VOL ne peut pas creer le volume tout seul"
            ;;
            *)
                if grep -q "destination ${d}.* has been modified" $L; then
                    MYZOPTS=$ZOPTS" -Bj"
                    syslogue "warning" "get_zfs(${s}@${DEST}): Deuxieme tentative avec -B"
                    descpb="force rollback"
                fi
            ;;
        esac
        if [ -n "$MYZOPTS" ]; then
            shellex $ZFS_SYNC_VOL $ZRECURSION $ZEXCLUDES $ZOPTS $MYZOPTS ${s}@${DEST} ${d} >> $L 2>&1
            ret=$?
        fi
        if [ $ret -eq 0 ]; then
            warn_admin $ret "get_zfs($*)" $L "WARNING: probleme auto-corrige ($descpb)"
        else
            warn_admin $ret "get_zfs($*)" $L "WARNING: Pb a la synchro du volume $1 (return $ret)"
        fi
    fi
    # mettre le flag "readonly"
    #zfs get -H -o name,value -t filesystem -r readonly ${d} | grep 'off$' | cut -f 1 | xargs -L1 zfs set readonly=on
    # TEMP: reverse ca: readonly s'herite
    #zfs get -H -o name,source -t filesystem -r readonly ${d} | grep -v '^'${d}'	' | cut -f 1 | xargs -L1 zfs inherit readonly
    zfs get -H -o name,value -t filesystem readonly ${d} | grep -q 'off$' && zfs set readonly=on ${d}
    [ -n "$DONOTEXCLUDEZFS" ] || now_exclude_zfs_only $s
    say_end_with $ret
}

zfs_presnap() {
    ZFS_PRESNAPS=$ZFS_PRESNAPS" "$($REMOTE_COMMAND $DEST "SNAP=\$(TZ=UTC date +GMT-%Y.%m.%d-%H.%M.%S); zfs snapshot -r ${1}@\$SNAP && echo ${1}@\$SNAP")
}

is_fstype() {
    for fst in $FSLIST; do
        [ "$fst" = "${1}:${2}" ] && return 0
    done
    return 1
}

#####################
### Jails FreeBSD ###
#####################
# retourne 0 si je jail est de type 'iocage'
# + place les variables curjail et curjaildir
is_iojail() {
    [ -z "$IOJAILS" ] && return 1
    echo $1 | fgrep -q iocage || return 1
    UUID=${1%/root*}
    UUID=${UUID#/iocage/jails/}
    [ -z "$UUID" ] && return 1
    # name-based iocage (0.9.9+) (UUID is name)
    curjail=${UUID}
    curjaildir="/iocage/jails/${UUID}"
    curjailroot="${curjaildir}/root"
    curjailsrc=$(get_zfs_src_for $curjaildir)
#echo "iocage 0.9.9+ curjail=$curjail curjaildir=$curjaildir curjailsrc=$curjailsrc"
    return 0
}

# retourne 0 si le chemin est celui d'un jail
# + place les variables curjail et curjaildir
is_jailed() {
    [ -z "$JAILS" ] && return 1
    [ "$1" = "/" ] && return 1
    for j in $JAILS; do
       ex=$(echo $j|sed 's@/@\\/@g')
       is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
       if expr "$test" : "$ex" >/dev/null || expr "$test" : "$ex" > /dev/null; then
           is_iojail $test && return 0
           curjail=${j##*/}
           curjaildir=${j}
           curjailroot=${j}
           curjailsrc=$(get_zfs_src_for $curjaildir)
           return 0
       fi
    done
    curjail=""
    curjaildir=""
    curjailsrc=""
    curjailroot=""
    return 1
}

# sauvegarde d'un jail
# get_jail jaildir
get_jail() {
    jaildir=$1
    is_jailed $jaildir || return 1
    is_excluded $jaildir && return 1

    L=$TRACES/$NAME.jail.$curjail

    syslogue "debug" "JAIL $curjail: BEGIN"

    zjdest=$JAILSZFSDEST/${curjail}
    jdest=$JAILSDESTDIR/${curjail}

    local ret=0
    local cret=0
    if is_iojail $jaildir; then
        syslogue "debug" "iocage curjail=$curjail curjaildir=$curjaildir curjailsrc=$curjailsrc"
        get_zfs ${curjaildir} $JAILSZFSDEST/$curjail ${curjailsrc}
        ret=$?
        now_exclude ${curjailsrc}
        [ "$SNAP_AFTER" = "YES" ] && snapshot_dest $JAILSZFSDEST/$curjail
        zfs list -H -o mountpoint,name,jailed -r $JAILSZFSDEST/$curjail | awk '{
          if($1 !~ /^'$(echo $jdest|sed 's@/@\\/@g')'/ && $1 ~ /^\//){
            rel=$1;
            gsub("^/$","",rel);
            if($3 ~ /^on$/){
              printf("zfs set orig:jailed=on jailed=off orig:mountpoint=%s mountpoint='$jdest'/root%s %s;\n",$1,rel,$2);
            }
            else{
              rdest=$1;
              gsub("'$curjaildir'","",rdest);
              gsub("^/$","",rdest);
              printf("zfs set mountpoint='$jdest'/root%s orig:mountpoint=%s %s;\n",rdest,$1,$2);
            }
          }
        }' > $TRACES/$NAME.$curjail.corrections_montages.sh 2>> $TRACES/$NAME.$curjail.corrections_montages.log
        echo "backup_from=$NAME" > $jdest.infos
        echo "last_backup=$(date)" >> $jdest.infos
    else
        if is_fstype zfs ${curjaildir}; then
syslogue "debug" "jail zfs curjail=$curjail curjaildir=$curjaildir curjailsrc=$curjailsrc"
            get_zfs ${curjaildir} $JAILSZFSDEST/$curjail ${curjailsrc}
            ret=$?
            now_exclude ${curjailsrc}
            zfs list -H -o mountpoint,name,jailed -r $JAILSZFSDEST/$curjail | awk '{
              if($1 !~ /^'$(echo $jdest|sed 's@/@\\/@g')'/ && $1 ~ /^\//){
                rel=$1;
                gsub("^/$","",rel);
                if($3 ~ /^on$/){
                  printf("zfs set orig:jailed=on jailed=off orig:mountpoint=%s mountpoint='$jdest'%s %s;\n",$1,rel,$2);
                }
                else{
                  printf("zfs set mountpoint='$jdest'%s orig:mountpoint=%s %s;\n",rdest,$1,$2);
                }
              }
            }' > $TRACES/$NAME.$curjail.corrections_montages.sh 2>> $TRACES/$NAME.$curjail.corrections_montages.log
        elif is_fstype ufs ${curjaildir}; then
syslogue "debug" "jail ufs curjail=$curjail curjaildir=$curjaildir curjailsrc=$curjailsrc"
            get_ufs ${curjaildir} $JAILSDESTDIR/$curjail $JAILSZFSDEST/$curjail
            ret=$?
            now_exclude ${curjaildir}
        else
syslogue "debug" "jail fs curjail=$curjail curjaildir=$curjaildir curjailsrc=$curjailsrc"
            get_fs ${curjaildir} $JAILSDESTDIR/$curjail
            ret=$?
            now_exclude ${curjaildir}
        fi
        [ "$SNAP_AFTER" = "YES" ] && snapshot_dest $JAILSZFSDEST/$curjail

        init_zfs_dest ${curjaildir}-config $JAILSDESTDIR/${curjail}-config $JAILSZFSDEST/${curjail}-config
        confdest="${jdest}-config"
        doit $REMOTE_COMMAND $DEST "mkdir -p /tmp/${curjail}-config; \
            ( [ -f /usr/local/etc/ezjail/${curjail} ] && cp /usr/local/etc/ezjail/${curjail} /tmp/${curjail}-config ) || \
                grep ^jail_${curjail} /etc/rc.conf > /tmp/${curjail}-config/rc.conf; \
            ( [ -f /etc/fstab.$curjail ] && cp /etc/fstab.$curjail /tmp/${curjail}-config ) || \
                ( [ -f ${dir%$curjail}fstab.$curjail ] && cp ${dir%$curjail}fstab.$curjail /tmp/${curjail}-config ); \
            hostname > /tmp/${curjail}-config/host; \
            tar -C /tmp/${curjail}-config -cf - .; rm -rf /tmp/${curjail}-config" | tar -C $confdest -xf - >> $L 2>&1
        ret=$?
        if [ $ret -ne 0 ]; then
            warn_admin $cret "get_jail($*)/get_config" $L "Pb pour recuperer la config du jail $curjail"
        fi
    fi
    if [ -s "$TRACES/$NAME.$curjail.corrections_montages.sh" ]; then
      syslogue "info" "JAIL $curjail: corrige montages"
      chmod +x $TRACES/$NAME.$curjail.corrections_montages.sh
      doit $TRACES/$NAME.$curjail.corrections_montages.sh
      zfs_mount_recurse $JAILSZFSDEST/$curjail
    fi
    syslogue "debug" "JAIL $curjail: END($(($ret+${cret})))"
}

## PROXMOX
# liste les stockages locaux
resolve_proxmox_storage() {
    storage=$1
    # dir
    d=$(echo "$PVESTORAGES" | grep "${1%:*}" | cut -d' ' -f1 | cut -d: -f2)
    # zfs source if any
    z=$(echo "$PVESTORAGES" | grep "${1%:*}" | cut -d' ' -f2)
    [ -n "$d" ] || return 1
    echo "${d}|${z}"
}
# sauvegarde d'un LXC
get_proxmox_lxc() {
    lxc_id=$1
    init_zfs_dest none ${PVEDESTDIR}/${lxc_id} ${PVEZFSDEST}/${lxc_id}
    doit $REMOTE_COMMAND $DEST "pct config $lxc_id" > ${PVEDESTDIR}/${lxc_id}/config
    echo $DEST > ${PVEDESTDIR}/${lxc_id}/host
    for disk in $(awk '/^(rootfs|mp[0-9]+):/{gsub(",.*","");if($2!="none"){printf("%s\n",$2);}}' ${PVEDESTDIR}/${lxc_id}/config); do
        if storage=$(resolve_proxmox_storage $disk); then
            if [ -n "${storage#*|}" ]; then
                get_zfs ${storage%|*}/${disk#*:} ${PVEZFSDEST}/${lxc_id}/${disk#*:} ${storage#*|}/${disk#*:}
            else
                get_fs ${storage%|*}/${disk#*:} ${PVEDESTDIR}/${lxc_id}/${disk#*:}
            fi
        fi
    done
}
# sauvegarde d'une VM qemu
get_proxmox_qemu() {
    qemu_id=$1
    init_zfs_dest none ${PVEDESTDIR}/${qemu_id} ${PVEZFSDEST}/${qemu_id}
    doit $REMOTE_COMMAND $DEST "qm config $qemu_id" > ${PVEDESTDIR}/${qemu_id}/config
    echo $DEST > ${PVEDESTDIR}/${qemu_id}/host
    for disk in $(awk '/^(virtio|scsi|ide)[0-9]+:/{gsub(",.*","");if($2!="none"){printf("%s\n",$2);}}' ${PVEDESTDIR}/${qemu_id}/config); do
        if storage=$(resolve_proxmox_storage $disk); then
            if [ -n "${storage#*|}" ]; then
                get_zfs ${storage%|*}/${disk#*:} ${PVEZFSDEST}/${qemu_id}/${disk#*:} ${storage#*|}/${disk#*:}
            else
                get_fs ${storage%|*}/${disk#*:} ${PVEDESTDIR}/${qemu_id}/${disk#*:}
            fi
        fi
    done
}
