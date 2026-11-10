#!/usr/bin/env bash
# The app list the user marks: one row per app, [x] = marked. Used by the install questions and by the
# menu's "Add apps" / "Remove apps". Written for bash 3.2+ (macOS) and Git Bash.
#
#      [x] = will be installed
#    > [x] OL Integration
#      [ ] TermIQ           needs OL Integration
#      ...
#      7 apps will be installed
#
# Keys: Up/Down move, Space marks or unmarks, A marks all, N marks none, Enter accepts the list.
# A terminal that cannot move the cursor (TERM=dumb) gets the same list with numbers to type instead.
# Drawing and key handling start no other processes (slow on Windows): a key press redraws at once.

# NEEDED_BY = the apps that need app $1 (the opposite of app_deps)
needed_by() {
  local a out=""
  for a in $APP_ORDER; do
    deps_of "$a"
    if in_list "$1" $DEPS; then out="$out $a"; fi
  done
  NEEDED_BY=${out# }
}

# Mark or unmark one app and keep the list consistent:
#   add mode    marking an app marks the apps it needs; unmarking one unmarks the apps that need it
#   remove mode the opposite: removing an app removes the apps that need it; keeping one keeps what it needs
pick_set() {   # pick_set <app> on|off
  local todo=$1 a d next keep
  while [ -n "$todo" ]; do
    next=""
    for a in $todo; do
      in_list "$a" $PICK_ROWS || continue
      if [ "$2" = on ]; then
        in_list "$a" $PICKED && continue
        PICKED="$PICKED $a"
        if [ "$PICK_MODE" = add ]; then deps_of "$a"; next="$next $DEPS"; else needed_by "$a"; next="$next $NEEDED_BY"; fi
      else
        in_list "$a" $PICKED || continue
        keep=""
        for d in $PICKED; do [ "$d" = "$a" ] || keep="$keep $d"; done
        PICKED=$keep
        if [ "$PICK_MODE" = add ]; then needed_by "$a"; next="$next $NEEDED_BY"; else deps_of "$a"; next="$next $DEPS"; fi
      fi
    done
    todo=$next
    case $todo in *[!\ ]*) ;; *) todo="" ;; esac   # only spaces: done
  done
  # keep the list order
  next=""
  for a in $PICK_ROWS; do if in_list "$a" $PICKED; then next="$next $a"; fi; done
  PICKED=${next# }
}

pick_count_line() {   # -> PICK_COUNT
  local n=0 a
  for a in $PICKED; do n=$((n + 1)); done
  case $n in
    0) if [ "$PICK_VERB" = installed ]; then PICK_COUNT="No apps marked: only the Hub will be installed"
       else PICK_COUNT="No apps marked: nothing will be $PICK_VERB"; fi ;;
    1) PICK_COUNT="1 app will be $PICK_VERB" ;;
    *) PICK_COUNT="$n apps will be $PICK_VERB" ;;
  esac
}

# Draw the list. Every row is cleared and written in full, so nothing old stays on the screen.
pick_draw() {   # pick_draw first|again|final
  local i=0 mark
  if [ "$1" != first ]; then printf '\033[%dA' "$PICK_LINES"; fi
  while [ $i -lt ${#PICK_APP[@]} ]; do
    mark="[ ]"
    if in_list "${PICK_APP[$i]}" $PICKED; then mark="[x]"; fi
    if [ "$1" != final ] && [ $i -eq "$PICK_CUR" ]; then
      printf '\r\033[K     %s>%s %s %s%-16s%s %s\n' "$C_ORANGE$C_BOLD" "$C_RESET" "$mark" "$C_BOLD" "${PICK_NAME[$i]}" "$C_RESET" "${PICK_NOTE[$i]}"
    else
      printf '\r\033[K       %s %-16s %s\n' "$mark" "${PICK_NAME[$i]}" "${PICK_NOTE[$i]}"
    fi
    i=$((i + 1))
  done
  pick_count_line
  printf '\r\033[K     %s\n' "$PICK_COUNT"
}

# Read one key -> KEY: up, down, toggle, all, none, done or other.
# Escape sequences are read to their end: arrows count, anything else a terminal sends (focus reports...) is ignored.
pick_key() {
  local c n
  KEY=other
  IFS= read -rsn1 -d '' c || { KEY=done; return 0; }
  case $c in
    $'\n'|$'\r') KEY=done ;;
    # the letter keys also work with the keyboard in Hebrew (X = ס, A = ש, N = מ, K = ל, J = ח)
    ' '|x|X|ס) KEY=toggle ;;
    a|A|ש) KEY=all ;;
    n|N|מ) KEY=none ;;
    k|K|ל) KEY=up ;;
    j|J|ח) KEY=down ;;
    $'\033')
      IFS= read -rsn1 -d '' -t 1 c || return 0
      case $c in
        '['|O)
          # parameters, then one final character (code 64..126): A = up, B = down
          while IFS= read -rsn1 -d '' -t 1 c; do
            printf -v n '%d' "'$c"
            if [ "$n" -ge 64 ] && [ "$n" -le 126 ]; then
              case $c in A) KEY=up ;; B) KEY=down ;; esac
              break
            fi
          done ;;
        ']'|P|_|'^')
          # a terminal report: skip to its end (BEL or ESC \)
          while IFS= read -rsn1 -d '' -t 1 c; do
            case $c in $'\a') break ;; $'\033') IFS= read -rsn1 -d '' -t 1 c || true; break ;; esac
          done ;;
      esac ;;
  esac
}

# The numbered list, for terminals that cannot move the cursor
pick_by_number() {
  local i mark ans
  while :; do
    i=0
    while [ $i -lt ${#PICK_APP[@]} ]; do
      mark="[ ]"
      if in_list "${PICK_APP[$i]}" $PICKED; then mark="[x]"; fi
      printf '     %2d %s %-16s %s\n' $((i + 1)) "$mark" "${PICK_NAME[$i]}" "${PICK_NOTE[$i]}"
      i=$((i + 1))
    done
    pick_count_line
    printf '     %s\n' "$PICK_COUNT"
    ask_read ans "     Type a number to mark or unmark that app, or press Enter when the list is right: " || return 0
    ans=$(first_number "$ans")
    [ -n "$ans" ] || return 0
    if [ "$ans" -lt 1 ] || [ "$ans" -gt ${#PICK_APP[@]} ]; then echo "     There is no number $ans."; continue; fi
    i=$((ans - 1))
    if in_list "${PICK_APP[$i]}" $PICKED; then pick_set "${PICK_APP[$i]}" off; else pick_set "${PICK_APP[$i]}" on; fi
    echo
  done
}

# pick_apps add|remove <verb> "<apps to list>" "<apps marked at the start>" -> PICKED
#   verb: installed | added | removed  (the legend says: [x] = will be <verb>)
pick_apps() {
  PICK_MODE=$1; PICK_VERB=$2; PICK_ROWS=$3; PICKED=""
  local a up down done_text
  PICK_APP=(); PICK_NAME=(); PICK_NOTE=()
  for a in $PICK_ROWS; do
    PICK_APP+=("$a")
    name_of "$a"; PICK_NAME+=("$NAME")
    deps_of "$a"
    if [ -n "$DEPS" ]; then app_names_v "$DEPS"; PICK_NOTE+=("needs $NAMES"); else PICK_NOTE+=(""); fi
  done
  [ ${#PICK_APP[@]} -gt 0 ] || { echo "     (no apps to choose)"; return 0; }
  for a in $4; do pick_set "$a" on; done
  PICK_LINES=$(( ${#PICK_APP[@]} + 1 )); PICK_CUR=0

  printf '     [x] = will be %s\n' "$PICK_VERB"
  if [ "${TERM:-dumb}" = dumb ] || [ "${OLHUB_NUMBERED_LIST:-}" = 1 ]; then
    echo
    pick_by_number
    return 0
  fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) up="↑"; down="↓" ;;
    *) up="Up"; down="Down" ;;
  esac
  done_text="done"
  [ "$PICK_VERB" != removed ] || done_text="remove the marked apps"
  printf '     %s %s move    Space mark / unmark    A all    N none    Enter %s\n\n' "$up" "$down" "$done_text"
  [ ! -t 1 ] || printf '\033[?1004l'   # no focus reports from the terminal while keys are read
  flush_input
  pick_draw first
  while :; do
    pick_key
    case $KEY in
      up)     PICK_CUR=$(( (PICK_CUR + ${#PICK_APP[@]} - 1) % ${#PICK_APP[@]} )) ;;
      down)   PICK_CUR=$(( (PICK_CUR + 1) % ${#PICK_APP[@]} )) ;;
      toggle) a=${PICK_APP[$PICK_CUR]}
              if in_list "$a" $PICKED; then pick_set "$a" off; else pick_set "$a" on; fi ;;
      all)    for a in $PICK_ROWS; do pick_set "$a" on; done ;;
      none)   for a in $PICK_ROWS; do pick_set "$a" off; done ;;
      done)   pick_draw final; return 0 ;;
      *)      continue ;;
    esac
    pick_draw again
  done
}
