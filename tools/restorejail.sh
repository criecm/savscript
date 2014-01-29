#!/bin/sh
#
# script de restauration d'un jail
#
# usage: $0 jail serv
#
if [ $# -ne 2 ]; then
  echo "usage: $0 jail host"
fi

