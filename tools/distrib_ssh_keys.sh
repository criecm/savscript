#!/bin/sh
#
# envoyer la cle ssh dans authorized_keys de la machine
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
  if ! ssh -oPasswordAuthentication=no -oStrictHostKeyChecking=yes -oIdentitiesOnly=yes -oIdentityFile=$SSH_KEY -oKbdInteractiveDevices=none root@$DEST "echo connexion ssh ok" || [ -n "$FORCE" ]; then
    ssh-keygen -R $DEST
    IP=$(host -t a $DEST | fgrep 'has address' | awk '{print $NF}')
    ssh-keygen -R $IP
    echo "pousse la cle sur ${DEST}:"
    echo "from=\""$(ssh -o "StrictHostKeyChecking=no" $DEST "echo \$SSH_CONNECTION"| awk '{print $1}')"\"$prepend $(cat $SSH_KEY.pub)" > /tmp/k
    cat /tmp/k | ssh root@$DEST "cat >> .ssh/tmpkey; ( fgrep -v \"$(cut -d' ' -f2 $SSH_KEY.pub)\" .ssh/authorized_keys ${OLD_KEY:+| fgrep -v \"$(cut -d' ' -f2 $SSH_KEY.pub)\"} ; cat .ssh/tmpkey ) > .ssh/authorized_keys.new && mv .ssh/authorized_keys .ssh/authorized_keys.bak && mv .ssh/authorized_keys.new .ssh/authorized_keys && rm -f .ssh/tmpkey"
  fi
done
