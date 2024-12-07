# fonction commune 

syslogue() {
  prio=${1:-notice}
  shift
  logger -p $SYSLOG_FACILITY.$prio -t"$SYSLOG_TAG[$$]" $@
  [ $DEBUG -ge 1 ] || [ "$prio" = "error" ] || [ "$prio" = "crit" ] && echo "[${prio}]: $*" >&2
  [ $DEBUG -gt 0 ] && [ "$prio" != "debug" ] && echo "[${prio}]: $*"
}

