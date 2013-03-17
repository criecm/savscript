#!/bin/sh
#
# include pour chaque script serveur
#
# utilise les variables "$NAME","$DEST","$excludes"
. /usr/local/admin/utils/common/common.sh.inc
. $mydir/lib/log.inc.sh

excludefrom=$TRACES/$NAME.excludes
ZFS_SYNC_VOL=$(which zfs_sync_vol)
ZEXCLUDES="-x $excludefrom.zfs"
#ZOPTS="-k $SSH_KEY -C -m 'GMT-%Y.%m.%d-%H.%M.%S' -I"
ZOPTS="-k $SSH_KEY -C -I -u"
ZRECURSION="-a"

if [ $DEBUG -ge 4 ]; then
    ZOPTS=$ZOPTS" -vv"
    doit() {
        syslogue "debug" "($NAME) DID NOT(DEBUG): $*"
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
# use: rsync_it srcdir/ dstdir/
rsync_it() {
    [ $DEBUG -ge 2 ] && RSYNC_OPTS=$RSYNC_OPTS" -v"
    doit $RSYNC_COMMAND $RSYNC_OPTS $(rsync_excludes_for ${1}) ${RSYNC_SRV_BASE}${1} ${2}
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
    test -z "$EXCLUDES" && return 1
    [ "$1" = "/" ] && return 1
    for excluded in $(echo $EXCLUDES | sed 's@/@\\/@g'); do
        expr "$1" : "${excluded%/}" >/dev/null && return 0
    done
    return 1
}

# construit une liste d'exclusions pour rsync
rsync_excludes_for() {
    test -z "$EXCLUDES" && return 1
    for x in $EXCLUDES; do
        case $x in
        /)
            syslogue "error" "excluding / ?"
            tmpargs=$tmpargs"--exclude \"/\""
        ;;
        /*)
            expr "$1" : "$(echo $x|sed 's@/@\\/@g; s@\.@\\.@g;')" >/dev/null && tmpargs=$tmpargs"--exclude \"${x#$1}\" "
        ;;
        *)
            tmpargs=$tmpargs"--exclude \"$x\" "
        ;;
        esac
    done
    echo "$tmpargs"
}

# exclus un chemin de la suite
now_exclude() {
    EXCLUDES=$EXCLUDES" "$1
}

# exclus un volume ZFS pour la suite
now_exclude_zfs() {
    grep -q ^$1 $excludefrom.zfs 2>/dev/null || echo $1 >> $excludefrom.zfs
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
# si FreeBSD:
#   - JAILS (liste de repertoires)
#   - ZPOOLS (pools zfs)
#   - ZFSSLASH (racine ZFS si 'legacy')
#   - ZFSFSES (zfs filesystems)
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
  echo JAILS=\\\"\$(/usr/sbin/jls | awk '(\$1 ~ /^[0-9]+\$/) { printf(\"%s\\\n\",\$4); }')\\\";
  if [ \$(mount -t zfs | wc -l) -gt 0 ]; then
    echo ZPOOLS=\\\"\$(/sbin/zpool list -H -o name)\\\";
    echo ZFSSLASH=\\\"\$(zfs list -H -omountpoint,name / | grep 'legacy' | awk '{print \$2}')\\\";
    echo ZFSFSES=\\\"\$(zfs list -H -t filesystem -o mountpoint,name | sed \$SEDOPT 's/[[:space:]]+/|/')\\\";
  fi
fi" > $srvinfos 2> $TRACES/$NAME.init_srv
        . $srvinfos > $TRACES/$NAME.init_srv 2>&1
    else
        aiiie "Serveur $DEST down. Pas de sauvegarde"
        return 1
    fi
    
    ### on a les infos du serveur: on les digere
    if [ "$SYSTEM" = "FreeBSD" ]; then
        #on cree le fichier d'exclusions pour zfs
        test -f $excludefrom.zfs && rm $excludefrom.zfs
        # traduit les exclusions de repertoires en volumes zfs
        if [ ! -z "$EXCLUDES" -a ! -z "$ZFSFSES" ]; then
            for zfsdesc in $ZFSFSES; do
                is_excluded "${zfsdesc%|*}" && now_exclude_zfs "${zfsdesc#*|}"
            done
        fi
        for fsdesc in $FSLIST; do
            case ${fsdesc%:*} in
                zfs) ZFS=YES ;;
                ufs) UFS=YES; NONZFS=YES ;;
                *) OTHERFS=YES; NONZFS=YES ;;
            esac
        done
        # si ZFS a la source
        if [ ! -z "$ZFSFSES" ]; then
            if [ ! -x "$ZFS_SYNC_VOL" ]; then
                warn_admin 1 "init_srv($*)" "" "Impossible de trouver zfs_sync_vol dans $PATH \!"
                return 1
            fi
            # si ZFS only: pas besoin de demon rsync
            if [ -n "$ZFS" -a -z "$NONZFS" ]; then
                FULLZFS=YES
                if [ $(expr "$ZPOOLS" : ".* ") -eq 0 ]; then
                    ONEZPOOL=$ZPOOLS
                fi
            fi
        fi
    fi

    if [ ! -z "$SYSVER" -a ! -z "$FSLIST" ]; then
        trap cleanup_srv 2 3
    else
        warn_admin 1 "init_srv($1)" "$TRACES/$NAME.init_srv" "Impossible d'initialiser la sauvegarde"
        return 1
    fi


    if [ -z "$FULLZFS" ]; then
        get_rsync_daemon
        if [ ! -z "$RSYNC_SRV_PID" ] && $RSYNC --port=$RSYNC_PORT ${DEST}:: >/dev/null 2>&1; then
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
        eval $($REMOTE_COMMAND $DEST 'RSYNC_SRV_DIR=/tmp/SAV.rsyncd
MYADDR=$(echo ${SSH_CONNECTION} | awk "{print \$3}")
if [ -d $RSYNC_SRV_DIR ]; then
  test -f $RSYNC_SRV_DIR/rsyncd.pid && kill $(cat $RSYNC_SRV_DIR/rsyncd.pid)
  rm -rf $RSYNC_SRV_DIR
  pgrep -f "rsync.*/tmp/SAV" && pkill -9 -f "rsync.*/tmp/SAV"
fi
if mkdir $RSYNC_SRV_DIR; then
  cat > $RSYNC_SRV_DIR/rsyncd.conf << EOF
uid = root
gid = 0
use chroot = no
max connections = 4
syslog facility = daemon
address = $MYADDR
port = '$RSYNC_PORT'
pid file = $RSYNC_SRV_DIR/rsyncd.pid
log file = $RSYNC_SRV_DIR/rsyncd.log
[root]
	path = /
	hosts allow = ${SSH_CLIENT%% *}
	read only = true
EOF
  if rsync --daemon --config=$RSYNC_SRV_DIR/rsyncd.conf < /dev/null; then
    echo export RSYNC_SRV_PID=$(cat $RSYNC_SRV_DIR/rsyncd.pid)
  fi
fi' 2> $TRACES/$NAME.get_rsync_daemon)
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
    return 0
}

#######################
### ZFS destination ###
#######################
is_zfs_path() {
    case "$1" in
    /*) return 0 ;;
    *) return 1 ;;
    esac
    return 0
}

# determine le rep destination pour une source
get_destdir_for() {
    is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
    if is_jailed $test; then
        echo $JAILSDESTDIR/$curjail${test#$curjaildir}
    else
        echo $DESTDIR${test%*/}
    fi
}

# determine la destination ZFS
get_zfsdest_for() {
    is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
    if is_jailed $test; then
        echo $JAILSZFSDEST/$curjail${test#$curjaildir}
    else
        echo $ZFSDEST${test%*/}
    fi
}

# renvoie le chemin ZFS de la source pour un repertoire
get_zfs_src_for() {
    for zfsdesc in $ZFSFSES; do
        if [ "$1" = "${zfsdesc%|*}" ]; then
            echo "${zfsdesc#*|}"
            return
        fi
    done
    return 1
}

# renvoie le chemin sur la source pour un volume ZFS source
get_srcdir_for_zfs() {
    for zfsdesc in $ZFSFSES; do
        if [ "$1" = "${zfsdesc#*|}" ]; then
            echo ${zfsdesc%|*}
            return
        fi
    done
    return 1
}

# creation d'un volume ZFS si besoin, verification du montage
# usage: init_zfs_dest <srcdir> [dstdir] [zfsdst]
# cree les variable:
#   $mydestdir (rep de sauvegarde pour ce chemin)
#   $myzfsdest (vol zfs correspondant)
init_zfs_dest() {
    mydir=$1
    L=$TRACES/$NAME.init_zfs_dest.$(echo $1 | sed 's@/@_@g')
    mydestdir=${2:-$(get_destdir_for $mydir)}
    myzfsdest=${3:-$(get_zfsdest_for $mydir)}
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
        while ! zfs list -H -o name ${myzpath%/*}; do
            ztocreate=${myzpath%/*}" "$ztocreate
            myzpath=${myzpath%/*}
        done
        for zc in $ztocreate; do
            doit zfs create -o canmount=off -o orig:mountpoint=none -o orig:canmount=off $ztocreate
        done
        zfs create -o orig:mountpoint=$mydir $myzfsdest

#        if [ -d $mydestdir.tmp ]; then
#            cd $mydestdir.tmp 2>> $L && \
#            doit pax -rw -X -pe . $mydestdir 2>> $L && \
#            cd - >/dev/null 2>> $L&& \
#            doit nohup rm -rf $mydestdir.tmp > $L 2>&1 &
#            warn_admin 0 "init_zfs_dest($*)" "$L" "Le contenu de $mydestdir.tmp a ete deplace dans le volume ZFS $mydestdir :)"
#        fi
    else
        # verifier que la destination est bien montee
        mount | grep -q ^$myzfsdest' ' && doit zfs umount $myzfsdest
        # MAJ orig:mountpoint
        if [ "$(zfs get -H -ovalue orig:mountpoint $myzfsdest)" != "$1" ]; then
            doit zfs set orig:mountpoint=$1 $myzfsdest
        fi
        if [ "$(zfs get -H -o value readonly ${myzfsdest})" != "off" ]; then
            zfs set readonly=off $myzfsdest
        fi
        doit zfs mount $myzfsdest
    fi
}

###########################
### Filesystems sources ###
###########################
# generique: rsync 'simple'
get_fs() {
    dir=$1
    say_begin "$dir"
    init_zfs_dest $dir $2 $3
    L=$TRACES/$NAME.get_fs.$(echo $1 | sed 's@/@_@g')
    rsync_it ${dir%/}/ $mydestdir/ >> $L 2>&1
    ret=$?
    shellex $ZFS_SNAP_MAKE -q $myzfsdest
    if [ $ret -ne 0 ]; then
        warn_admin $ret "get_fs($*)" $L "Pb avec $RSYNC_COMMAND $RSYNC_DSTBASE${dir}"
    fi
    say_end_with $ret
}

# usage: get_ufs srcdir [[dstdir] [zfsdest]]
get_ufs() {
    dir=$1
    say_begin "UFS:$dir"
    L=$TRACES/$NAME.get_ufs.$(echo $1 | sed 's@/@_@g')
    UFSSNAPNAME=rsync.$(date +%Y%m%d-%H%M%S)
    UFSMOUNTDIR=/tmp/mntsav_$(hostname -s)$(echo ${dir%/}|sed 's@/@_@g')
    # creation du snapshot a la source
    if [ ${SYSVER%%.*} -gt 5 ]; then
        UFSTS=$($REMOTE_COMMAND $DEST "\
            if [ -d \"${dir}\" ] && [ -d ${dir%/}/.snap ]; then \
              if mount -u -o snapshot ${dir%/}/.snap/$UFSSNAPNAME ${dir}; then \
                TS=\$(TZ=UTC date +%s)
                mkdir -p $UFSMOUNTDIR; \
                if mount -r /dev/\$(mdconfig -a -t vnode -o readonly -f ${dir%/}/.snap/$UFSSNAPNAME) $UFSMOUNTDIR; then \
                  echo \$TS; \
                else \
                  mdconfig -l -v | grep $UFSSNAPNAME | cut -f1 | xargs -L1 mdconfig -d -u ; \
                  rm -f ${dir%/}/.snap/$UFSSNAPNAME 2>/dev/null; \
                fi \
              else \
                test -f ${dir%/}/.snap/$UFSSNAPNAME && rm -f ${dir%/}/.snap/$UFSSNAPNAME; \
              fi \
            fi") >> $L 2>&1 || return 1
    fi
    init_zfs_dest $dir $2 $3
    if [ ! -z "$UFSTS" ]; then
        rsync_it ${UFSMOUNTDIR}/ $mydestdir/ >> $L 2>&1
        ret=$?
        # menage du snapshot source
        $REMOTE_COMMAND $DEST "umount $UFSMOUNTDIR || ( fuser -k -m $UFSMOUNTDIR ; umount -f $UFSMOUNTDIR ); \
            mdconfig -l -v | fgrep ${dir%/}/.snap/$UFSSNAPNAME | cut -f1 | xargs -L1 mdconfig -d -u && rm -f ${dir%/}/.snap/$UFSSNAPNAME && rmdir $UFSMOUNTDIR;" || syslogue "error" "AIIIE: snapshot impossible a supprimer: ${dir%/}/$UFSSNAPNAME monte sur $UFSMOUNTDIR" >> $L 2>&1
    else
        [ ${SYSVER%%.*} -gt 5 ] && syslogue "notice" "get_ufs($dir): pas reussi a utiliser un snapshot :-/"
        rsync_it ${dir%/}/ $mydestdir/ >> $L 2>&1
        ret=$?
    fi
    shellex $ZFS_SNAP_MAKE -q ${UFSTS:+-s $UFSTS} $myzfsdest
    if [ $ret -ne 0 ]; then
        syslog "error" "Probleme a la sauvegarde de ${DEST}:${dir} (UFS+snapshot)"
        warn_admin $ret "get_ufs($*)" $L "Pb avec $RSYNC_COMMAND$RSYNC_DSTBASE$UFSMOUNTDIR"
    fi
    say_end_with $ret
}

# usage: get_zfs srcdir [dstvol] [srcvol]
get_zfs() {
    if [ "$1" = "legacy" ]; then
        return
    fi
#    echo "get_zfs $*" >> /tmp/$(echo "$DEST $*" | sed 's/[^-a-zA-Z0-9]/_/g')
    ztarget=$1
    d=${2:-$(get_zfsdest_for $ztarget)}
    s=${3:-$(get_zfs_src_for $ztarget)}
    L=$TRACES/$NAME.get_zfs.$(echo $1 | sed 's@/@_@g')
    if [ -z "$d" -o -z "$s" ]; then
        warn_admin 1 "get_zfs($*)" "" "get_zfs($1): impossible de trouver la destination($d) ou le repertoire ($s)"
        return 1
    fi
    say_begin "ZFS:$ztarget"
    [ $DEBUG -gt 0 ] && echo "DEBUG: shellex $ZFS_SYNC_VOL $ZRECURSION $ZEXCLUDES $ZOPTS ${s}@${DEST} ${d}"
    shellex $ZFS_SYNC_VOL $ZRECURSION $ZEXCLUDES $ZOPTS ${s}@${DEST} ${d} >> $L 2>&1
    ret=$?
    if [ $ret -ne 0 ]; then
        if fgrep -q 'No common snapshot' $L; then
            syslogue "notice" "Deuxieme tentative avec -j pour get_zfs(${s})"
            shellex $ZFS_SYNC_VOL $ZRECURSION $ZEXCLUDES $ZOPTS -j ${s}@${DEST} ${d} >> $L 2>&1
            ret=$?
        fi
        warn_admin $ret "get_zfs($*)" $L "Pb a la synchro du volume $1"
    fi
    # mettre le flag "readonly"
    zfs get -H -r -o name,value -t filesystem -r readonly ${d} | grep 'off$' | cut -f 1 | xargs -L1 zfs set readonly=on
    zfs set readonly=on ${d} >> $L 2>&1
    now_exclude_zfs $s
    say_end_with $ret
}

zfs_presnap() {
    ZFS_PRESNAPS=$ZFS_PRESNAPS" "$($REMOTE_COMMAND $DEST "SNAP=\$(TZ=UTC date +GMT-%Y.%m.%d-%H.%M.%S); zfs snapshot -r ${1}@\$SNAP && echo ${1}@\$SNAP")
}

#####################
### Jails FreeBSD ###
#####################

is_jailed() {
    [ -z "$JAILS" ] && return 1
    [ "$1" = "/" ] && return 1
    for j in $JAILS; do
       ex=$(echo $j|sed 's@/@\\/@g')
       is_zfs_path $1 && test=$(get_srcdir_for_zfs $1) || test=$1
       if expr "$test" : "$ex" >/dev/null || expr "$test" : "$ex" > /dev/null; then
           curjail=${j##*/}
           curjaildir=${j}
           return 0
       fi
    done
    curjail=""
    curjaildir=""
    return 1
}

# sauvegarde d'un jail
# get_jail jaildir
get_jail() {
    jaildir=$1
    is_jailed $jaildir || continue
    is_excluded $jaildir && continue
    # si c'est un sous-repertoire, c'est pas ici ...
    [ "$jaildir" = "$curjaildir" ] || continue
    L=$TRACES/$NAME.jail.$curjail
    say_begin " JAIL $curjail ("

    zjdest=$JAILSZFSDEST/$curjail
    jdest=$JAILSDESTDIR/$curjail

    if echo "$FSLIST" | fgrep -q "zfs:$jaildir" >/dev/null; then
        get_zfs $jaildir $JAILSZFSDEST/$curjail
    else
        get_ufs $jaildir $JAILSDESTDIR/$curjail $JAILSZFSDEST/$curjail
    fi
    now_exclude_zfs $jaildir
    now_exclude $jaildir

    init_zfs_dest ${jaildir}-config $JAILSDESTDIR/${curjail}-config $JAILSZFSDEST/${curjail}-config
    confdest="${jdest}-config"
    doit $REMOTE_COMMAND $DEST "mkdir -p /tmp/${curjail}-config; \
        ( [ -f /usr/local/etc/ezjail/${curjail} ] && cp /usr/local/etc/ezjail/${curjail} /tmp/${curjail}-config ) || \
            fgrep ^jail_${curjail} /etc/rc.conf > /tmp/${curjail}-config/rc.conf; \
        ( [ -f /etc/fstab.$curjail ] && cp /etc/fstab.$curjail /tmp/${curjail}-config ) || \
            ( [ -f ${dir%$curjail}fstab.$curjail ] && cp ${dir%$curjail}fstab.$curjail /tmp/${curjail}-config ); \
        tar -C /tmp/${curjail}-config -cf - .; rm -rf /tmp/${curjail}-config" | tar -C $confdest -xf - >> $L 2>&1
    cret=$?
    if [ $cret -ne 0 ]; then
        warn_admin $cret "get_jail($*)/get_config" $L "Pb pour recuperer la config du jail $curjail"
    fi
    shellex $ZFS_SNAP_MAKE -q $confdest
    say_end_with $(($ret+$cret)) ")"
}

