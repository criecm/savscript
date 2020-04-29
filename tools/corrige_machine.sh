#!/bin/sh
if [ $# -ne 1 ] || ! zfs list -H $SAVZFSBASE/$1 > /dev/null; then
  echo usage: $0 machine
fi
m=$1
me=$(hostname -s)

savpath=$(realpath "$(dirname $0)/..")
. $savpath/savscript.conf || exit 1

:>/tmp/$m.pb
for z in $(zfs list -r -H -o name $SAVZFSBASE/$m); do        
  zfs list -H -o name -t snapshot -r -d1 $z | grep $m-$me > /dev/null || echo $z >> /tmp/$m.pb
done
for fs in $(cat /tmp/$m.pb); do
  echo "$m | Corrige $fs"
  mntp=$(zfs get -H -o value mountpoint $fs | sed 's@'$SAVDESTBASE'/'$m'@@')
  canmount=$(zfs get -H -o value canmount $fs)
  if [ "$mntp" = "legacy" -o "${fs#$SAVZFSBASE/$m}" = "/ROOT/default" ]; then
    srcfs="/"
  elif [ "$canmount" = "off" ]; then
    for pool in $(ssh -i $SSH_KEY root@$m zpool list -H -o name); do
      srcfs=$(ssh -i $SSH_KEY root@$m zfs list -H -o name $pool/${fs#$SAVZFSBASE/$m})
      [ -n "$srcfs" ] && break
    done
  else
    srcfs=${fs#$SAVZFSBASE/$m}
  fi
  src=$( ssh -i $SSH_KEY root@$m zfs list -H -o name -r -d1 -t snapshot $srcfs | grep @$m-$(hostname -s) | tail -1 )
  if [ -n "$src" ]; then
    zfs umount $fs 2>/dev/null || zfs umount -f $fs 2>/dev/null
    zfs destroy -r $fs 2>/dev/null
    ssh -i $SSH_KEY root@$m zfs send $src | mbuffer | zfs receive -F $fs
  else
    echo "$m / $fs / $srcfs : impossible de trouver une source ($src)" >&2
  fi
done
:>/tmp/$m.pb
for zz in $(zfs list -r -H -o name $SAVZFSBASE/$m); do
  zfs list -H -o name -t snapshot -r -d1 $z | grep $m-$me > /dev/null || echo $z >> /tmp/$m.pb
done
if [ -s /tmp/$m.pb ]; then
  echo reste des pbs avec $m
  cat /tmp/$m.pb
fi
