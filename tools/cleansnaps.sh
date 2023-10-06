#!/bin/sh
export PATH=$PATH:/root/tools/scripts/zfs:/usr/local/admin/sysutils/zfs

savpath=$(realpath "$(dirname $0)/..")
. $savpath/savscript.conf || exit 1

date >> /var/log/cleansnaps.log
for m in $(ls $savpath/machines.d | grep conf$); do
  . $savpath/machines.d/$m
  if ! [ -n "$NAME" ]; then echo "$savpath/machines.d/$m: pas de NAME !!!"; continue; fi
  /usr/local/admin/sysutils/zfs/zfs_clean_snap -r 72h15d6w12m1y $SAVZFSBASE/$NAME | tee -a /var/log/cleansnaps.log
  zfs list -H -o name -r -t snapshot $SAVZFSBASE/$NAME | fgrep '@'$NAME'-' | fgrep -v '@'$NAME'-'$(hostname -s) | tee -a /var/log/cleansnaps.log | xargs -tL1 zfs destroy -d
done >> /var/log/cleansnaps.log

