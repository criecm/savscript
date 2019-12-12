#!/bin/sh
for m in $(ls machines.d | grep conf$ | sed s/.conf//); do
  /usr/local/admin/sysutils/zfs/zfs_clean_snap -r 72h15d6w12m1y zdata/sav/$m
done

