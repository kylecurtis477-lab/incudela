# tests/os/frozen.sh: box-freeze accounting for shell loops that wait on a guest (sourced; inv211).
# Like the boot harness (tests/os/boot.cud freeze_gap) and the kernel's irq-off watch (f2ffc23): while the box
# is frozen the guest does not run, but the host's clocks (and so `timeout`) keep going, and on resume a
# deadline fires for time the guest never had (os211b: forgefs boot 0 killed after a 12-minute freeze).
#   frz_start CAP   begin a run capped at CAP seconds of guest running time
#   frz_tick        call once per loop pass (passes are 1 s apart: the loop sleeps 1). A wall gap of 5 s or more
#                   since the previous pass is a box freeze: the time beyond the pass's own 1 s is not counted,
#                   the deadline moves out by exactly that time, and "[forgefs: box frozen Ns, not counted]" is
#                   printed and kept in FRZ_LOG. Returns 1 once the counted time reaches CAP (never earlier).
# FRZ_FAKE (milliseconds) replaces the clock for frz_self_test.
frz_now() { if [ -n "${FRZ_FAKE:-}" ]; then echo "$FRZ_FAKE"; else date +%s%3N; fi; }
frz_start() {
  FRZ_CAP=$(($1 * 1000)); FRZ_T0=$(frz_now); FRZ_PREV=$FRZ_T0; FRZ_FROZEN=0; FRZ_LOG=""
  FRZ_DEADLINE=$((FRZ_T0 + FRZ_CAP))
}
frz_tick() {
  local now gap f msg
  now=$(frz_now); gap=$((now - FRZ_PREV)); FRZ_PREV=$now
  if [ $gap -ge 5000 ]; then
    f=$((gap - 1000)); FRZ_FROZEN=$((FRZ_FROZEN + f)); FRZ_DEADLINE=$((FRZ_DEADLINE + f))
    msg="[forgefs: box frozen $((f / 1000)).$((f % 1000 / 100))s, not counted]"
    echo "$msg"; FRZ_LOG="$FRZ_LOG$msg"$'\n'
  fi
  [ $now -lt $FRZ_DEADLINE ]
}
frz_self_test() {  # synthetic clock: gaps of 4.999 s (counted), 5 s (4 s frozen) and 13 s (12 s frozen) in a 180 s run
  local bad="" t out stop=""
  out=$(mktemp)
  FRZ_FAKE=0; frz_start 180
  for t in 1000 2000 3000 7999; do FRZ_FAKE=$t; frz_tick > $out || bad="$bad; stopped at $t"; done
  [ $FRZ_FROZEN = 0 ] && [ ! -s $out ] || bad="$bad; a 4.999 s gap counted as frozen ($FRZ_FROZEN ms)"
  FRZ_FAKE=12999; frz_tick > $out || bad="$bad; stopped at 12999"
  [ $FRZ_FROZEN = 4000 ] && [ "$(cat $out)" = "[forgefs: box frozen 4.0s, not counted]" ] || bad="$bad; 5 s gap: frozen $FRZ_FROZEN ms, said '$(cat $out)'"
  FRZ_FAKE=25999; frz_tick > $out || bad="$bad; stopped at 25999"
  [ $FRZ_FROZEN = 16000 ] && [ "$(cat $out)" = "[forgefs: box frozen 12.0s, not counted]" ] || bad="$bad; 13 s gap: frozen $FRZ_FROZEN ms in total, said '$(cat $out)'"
  t=25999
  while [ -z "$stop" ] && [ $t -lt 400000 ]; do t=$((t + 1000)); FRZ_FAKE=$t; frz_tick > $out || stop=$t; done
  # guest time = wall - frozen: 195999 - 16000 = 179999 ms still runs, 196999 - 16000 = 180999 ms stops
  [ "$stop" = 196999 ] || bad="$bad; stopped at wall $stop ms, want 196999 (guest 180999 ms)"
  [ ! -s $out ] && [ "$FRZ_LOG" = "[forgefs: box frozen 4.0s, not counted]"$'\n'"[forgefs: box frozen 12.0s, not counted]"$'\n' ] || bad="$bad; log '${FRZ_LOG//$'\n'/ }'"
  stop=""; FRZ_FAKE=0; frz_start 180
  for t in $(seq 1000 1000 180000); do FRZ_FAKE=$t; frz_tick > $out || { stop=$t; break; }; done
  [ "$stop" = 180000 ] || bad="$bad; an unfrozen run stopped at $stop ms, want 180000"
  rm -f $out; unset FRZ_FAKE
  if [ -z "$bad" ]; then
    echo "PASS os/forgefs-freeze-accounting (gaps of 5 s and 13 s: 4 s and 12 s not counted, run ends at 180 s guest time; a 4.999 s gap and an unfrozen run count in full)"
  else
    echo "FAIL os/forgefs-freeze-accounting (${bad#; })"
  fi
}
