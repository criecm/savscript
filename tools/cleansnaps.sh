#!/bin/sh
export PATH=$PATH:/root/tools/scripts/zfs:/usr/local/admin/sysutils/zfs

savpath=$(realpath "$(dirname $0)/..")
. $savpath/savscript.conf || exit 1

date >> /var/log/cleansnaps.log
for m in $(ls $savpath/machines.d | grep conf$ | sed 's/\.conf//'); do
  /usr/local/admin/sysutils/zfs/zfs_clean_snap -r 72h15d6w12m1y $SAVZFSBASE/$m | tee -a /var/log/cleansnaps.log
  zfs list -H -o name -r -t snapshot $SAVZFSBASE/$m | fgrep '@'$m'-' | fgrep -v '@'$m'-'$(hostname -s) | tee -a /var/log/cleansnaps.log | xargs -L1 zfs destroy -d
done

