#!/bin/sh
#
# nouveau serveur a sauvegarder
#
if [ $# -lt 1 ]; then
  echo "usage: $0 serveur [serveur …]"
  exit
fi

. rsync_serveurs.conf || exit 1

prepend=",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc,no-pty"

if ! ssh -oPasswordAuthentication=no -oIdentitiesOnly=yes -oIdentityFile=/root/.ssh/id_rsyncsav -oKbdInteractiveDevices=none root@$1 "echo connexion ssh ok"; then
  echo "pousse la cle sur ${1}:"
  echo "from=\""$(ssh $1 "echo \$SSH_CONNECTION"| awk '{print $1}')"\"$prepend $(cat $SSH_KEY.pub)" > /tmp/k
  cat /tmp/k | ssh root@$1 "cat >> .ssh/authorized_keys"
fi
eval $(ssh -oPasswordAuthentication=no -oIdentitiesOnly=yes -oIdentityFile=/root/.ssh/id_rsyncsav -oKbdInteractiveDevices=none root@$1 'SYSTEM=`uname -s`; 
case "$SYSTEM" in
"Linux")
    case `lsb_release -si` in
    "Debian"|"Ubuntu")
        EXCLUDES="/var/cache/apt/archives"
    ;;
    esac
    FSLIST="`for fst in ext3 ext4 ext2 btrfs; do df -t $fst; done | tail -n +2 | awk '\''{print $6}'\''`"
;;
"FreeBSD")
    EXCLUDES="/usr/ports/distfiles /usr/obj"
    FSTYPES="ufs,zfs,ext3,ext2"
    JAILS=`jls | tail -n +2`
    FSLIST="`df -t'$FSTYPES' | tail -n +2 | awk '\''{print $6}'\''`"
;;
"OpenBSD")
    FSLIST="`df -tffs | tail -n +2 | awk '\''{print $6}'\''`"
;;
*)
    FSTYPES=`echo '$FSTYPES' | sed "s/,/ /"`
    FSLIST="`for fst in $FSTYPES; do echo $fst; done | xargs -t -L1 df -t | tail -n +2 | awk '\''{print $6}'\''`"
;;
esac
echo SYSTEM="$SYSTEM"
echo EXCLUDES=\"$EXCLUDES\"
echo RSYNC=\"`which rsync`\"
echo MYIP=\"`echo $SSH_CONNECTION | cut -d" " -f3`\"
echo JAILS=\"$JAILS\"
echo FSLIST=\"$FSLIST\"
echo MYNAME="`hostname -s`"')

echo SYSTEM=$SYSTEM
echo EXCLUDES="$EXCLUDES"
echo RSYNC=$RSYNC
MYFQDN=$(getent hosts $MYIP | awk '{print $2}')
echo "MYIP=$MYIP ($MYFQDN)"
echo MYNAME=$MYNAME
echo FSLIST="$FSLIST"

if [ -z "$MYNAME" -o -z "$MYIP" -o -z "$MYFQDN" -o -z "$RSYNC" -o -z "$SYSTEM" ]; then
  exit 1
fi

sed -E 's/%%NAME%%/'$MYNAME'/; s/%%FQDN%%/'$MYFQDN'/; s@%%EXCLUDES%%@'"$EXCLUDES"'@;' machines.d/conf.template > /tmp/$MYNAME.conf

echo La conf generee:
echo -- "##############################################################################"
cat /tmp/$MYNAME.conf
echo -- "##############################################################################"

if [ -f machines.d/$MYNAME.conf ]; then
  echo "machines.d/$MYNAME.conf existe (la supprimer avant pour la remplacer)"
  exit 1
fi

echo "On l'installe ? (ENTREE ou CTRL+C)"
read p
mv /tmp/$MYNAME.conf machines.d/$MYNAME.conf

