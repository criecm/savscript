# fonction commune 

syslogue() {
  prio=${1:-notice}
  shift
  logger -p $SYSLOG_FACILITY.$prio -t"$SYSLOG_TAG[$$]" $@
  [ $DEBUG -gt 0 -o "$prio" = "error" -o "$prio" = "crit" ] && echo "$(date) [${prio}]: $*" >&2
}

