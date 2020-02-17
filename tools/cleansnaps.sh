#!/bin/sh
export PATH=$PATH:/root/tools/scripts/zfs:/usr/local/admin/sysutils/zfs
savzfs=$(zfs list -H -o name /sav)
[ -n "$savzfs" ] || exit 1
for m in $(ls machines.d | grep conf$ | sed s/.conf//); do
  zfs_clean_snap -r 72h15d6w12m1y $savzfs/$m
done

