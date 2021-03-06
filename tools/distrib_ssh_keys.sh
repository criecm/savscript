#!/bin/sh
#
# envoyer la cle ssh dans authorized_keys de la machine
# (nécéssite une cle deja autorisee et chargée dans ssh-agent)
#
# si $OLD_KEY est definie, la supprime des authorized_keys
# si $FORCE est defini, re-ecrit les authorized_keys
#
savpath=$(realpath "$(dirname $0)/..")
. $savpath/savscript.conf || exit 1

prepend=",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty"

[ -f "$SSH_KEY" ] || exit 1

if [ $# -eq 0 ]; then
  echo "usage: $0 all|machine1 [machine2 ...]"
  exit 1
fi

if [ "$1" = "all" ]; then
  machines=$(for i in $savpath/machines.d/*.conf; do echo ${i%.conf} | sed 's@.*/@@g'; done)
  shift
else
  machines=$@
  shift $#
fi

for m in $machines; do
  eval $(grep ^DEST $savpath/machines.d/$m.conf)
  [ -z "$DEST" ] && DEST=$m
  echo -n "$m($DEST): "
  if ! ssh -oConnectTimeout=2 -oPasswordAuthentication=no -oStrictHostKeyChecking=yes -oIdentitiesOnly=yes -oIdentityFile=$SSH_KEY -oKbdInteractiveDevices=none root@$DEST "echo is ok." || [ -n "$FORCE" ]; then
    MYIP4=$(ssh -4 -oConnectTimeout=2 -oPasswordAuthentication=no -oStrictHostKeyChecking=no -oKbdInteractiveDevices=none root@$DEST "echo \$SSH_CLIENT | awk '{print \$1}'")
    MYIP6=$(ssh -6 -oConnectTimeout=2 -oPasswordAuthentication=no -oStrictHostKeyChecking=no -oKbdInteractiveDevices=none root@$DEST "echo \$SSH_CLIENT | awk '{print \$1}'")
    ssh-keygen -R $DEST
    if [ -z "$MYIP6" ]; then
      MYIP=$MYIP4
    elif [ -z "$MYIP4" ]; then
      MYIP=$MYIP6
    else
      MYIP="$MYIP4,$MYIP6"
    fi
    IP=$(host -t a $DEST | fgrep 'has address' | awk '{print $NF}')
    IP6=$(host -t a $DEST | fgrep -i 'has IPv6 address' | awk '{print $NF}')
    echo "from=\"$MYIP\""
    [ ! -z "$IP" ] && ssh-keygen -R $IP
    [ ! -z "$IP6" ] && ssh-keygen -R $IP6
    ssh-keygen -R $DEST
    echo "from=\"$MYIP\"$prepend $(cat $SSH_KEY.pub)" > /tmp/k
    cat /tmp/k | ssh -oStrictHostKeyChecking=no root@$DEST "cat >> .ssh/tmpkey; ( fgrep -v \"$(cut -d' ' -f2 $SSH_KEY.pub)\" .ssh/authorized_keys ${OLD_KEY:+| fgrep -v \"$(cut -d' ' -f2 $SSH_KEY.pub)\"} ; cat .ssh/tmpkey ) > .ssh/authorized_keys.new && mv .ssh/authorized_keys .ssh/authorized_keys.bak && mv .ssh/authorized_keys.new .ssh/authorized_keys && rm -f .ssh/tmpkey"
    ssh -oConnectTimeout=2 -oPasswordAuthentication=no -oStrictHostKeyChecking=yes -oIdentitiesOnly=yes -oIdentityFile=$SSH_KEY -oKbdInteractiveDevices=none root@$DEST "echo is now ok."
  fi
done
