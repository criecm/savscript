#!/bin/sh
#
# verifications diverses des sauvegardes
#
. savscript.conf

# supprime une propriete (et la sauvegarde en orig:)
resetprop() {
  echo "RESETTING $prop on $vol (was \"$val\")" >&2
  echo zfs inherit $prop $vol
  echo zfs set orig:${prop}="${val}" $vol
} 

SAVDESTBASEREGEX="$(echo $SAVDESTBASE | sed 's@/@\\/@g; s/\./\\./g;')"
zfs get -H -oname,property,value,source -r all $SAVZFSBASE | grep -v '^'$SAVZFSBASE'$' | grep local$ | while read vol prop val src; do
  case $prop in
    mountpoint)
      if [ "$val" = "/" ]; then
        resetprop
      else
        expr "$val" : "$SAVDESTBASEREGEX" >/dev/null || resetprop
      fi
    ;;
    sharenfs)
      resetprop
    ;;
    sharesmb)
      resetprop
    ;;
    dedup)
      resetprop
    ;;
    primarycache)
      resetprop
    ;;
  esac
done
