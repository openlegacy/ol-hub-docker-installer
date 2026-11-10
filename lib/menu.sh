#!/usr/bin/env bash
# The menu: what ./ol-hub-docker.sh (and a double-click on ol-hub-docker.cmd) shows. Every choice runs the same
# command a user could type (./ol-hub-docker.sh <command>), in its own process, then comes back here.

MENU_KEYS=(); MENU_LABELS=()
menu_add() { MENU_KEYS+=("$1"); MENU_LABELS+=("$2"); }

# Run one of this script's commands, then wait for Enter
menu_run() {
  local conf=""
  [ "$CONF_FILE" = "$ROOT/install.conf" ] || conf="-c $CONF_FILE"
  echo
  bash "$ROOT/ol-hub-docker.sh" $conf "$@" || true
  echo
  ask_read __x "Press Enter to return to the menu " || exit 0
}

# Pick one service by number (restart / logs); prints it, "" for everything
menu_pick_service() {   # menu_pick_service "<title>"
  local svcs="everything proxy postgres keycloak ol-hub $INSTALLED_APPS" i=1 s choice
  echo "$1" >&2
  for s in $svcs; do
    case $s in
      everything) printf '  %2d) everything\n' $i >&2 ;;
      ol-*)       printf '  %2d) %-16s %s\n' $i "$s" "$(app_name "$s" | sed 's/^ol-hub$/OpenLegacy Hub/')" >&2 ;;
      *)          printf '  %2d) %s\n' $i "$s" >&2 ;;
    esac
    i=$((i + 1))
  done
  ask_read choice "Choose a number: " || return 1
  choice=$(first_number "$choice")
  case $choice in ''|*[!0-9]*) return 1 ;; esac
  s=$(printf '%s\n' $svcs | sed -n "${choice}p")
  [ -n "$s" ] || return 1
  [ "$s" = everything ] && s=""
  printf '%s' "$s"
}

# The apps that are not installed yet, to mark; exactly the marked ones (and the apps they need) are added
menu_add_apps() {
  local a rows=""
  for a in $APP_ORDER; do in_list "$a" $INSTALLED_APPS || rows="$rows $a"; done
  rows=$(trim "$rows")
  [ -n "$rows" ] || { echo "Every app is installed already."; ask_read __x "Press Enter to return to the menu " || true; return 0; }
  echo
  echo "     Apps that are not installed yet. Mark the ones to add."
  pick_apps add added "$rows" ""
  if [ -z "$PICKED" ]; then echo "     No app marked - nothing changes."; ask_read __x "Press Enter to return to the menu " || true; return 0; fi
  menu_run add $PICKED
}

# The installed apps, to mark; exactly the marked ones (and the apps that need them) are removed
menu_remove_apps() {
  local purge=""
  [ -n "$INSTALLED_APPS" ] || { echo "No apps are installed."; ask_read __x "Press Enter to return to the menu " || true; return 0; }
  echo
  echo "     The installed apps. Mark the ones to remove."
  pick_apps remove removed "$INSTALLED_APPS" ""
  if [ -z "$PICKED" ]; then echo "     No app marked - nothing changes."; ask_read __x "Press Enter to return to the menu " || true; return 0; fi
  echo
  if yes_no "     Also DELETE their data (cannot be undone)?" n; then purge="--purge"; fi
  menu_run remove $purge $PICKED
}

menu_ask_file() {   # menu_ask_file "<question>" "<default>" -> prints the answer
  local f
  ask_read f "$1${2:+ [$2]}: " || return 1
  f=$(trim "$f"); f=$(printf '%s' "$f" | sed "s/^[\"']//; s/[\"']\$//")
  printf '%s' "${f:-$2}"
}

do_menu() {
  local installed running choice key i hub_url s f
  # Ctrl+C stops what runs (e.g. watching the logs), not the menu
  trap 'echo' INT
  set_title "OpenLegacy Hub"
  while :; do
    load_config
    INSTALLED_APPS=$(installed_apps)
    installed=false; running=false; hub_url=""
    if [ -n "$(cid ol-hub)" ] && [ -f "$ENV_FILE" ]; then
      installed=true
      hub_url=$(sed -n "s/^PUBLIC_HUB_URL='\(.*\)'\$/\1/p" "$ENV_FILE")
      if in_list "$(health_status ol-hub)" running healthy; then running=true; fi
    fi

    local apps_line="" n
    if [ -n "$INSTALLED_APPS" ]; then
      n=$(printf '%s\n' $INSTALLED_APPS | grep -c . || true)
      apps_line="$n app$([ "$n" = 1 ] || echo s) installed (\"Status\" lists them)"
    fi
    if [ "$installed" = false ]; then
      ol_banner "Not installed on this computer yet."
    elif [ "$running" = true ]; then
      ol_banner "Running: $hub_url" "$apps_line"
    else
      ol_banner "Installed, ${C_YELLOW}stopped${C_RESET} (choose \"Start everything\")" "$apps_line"
    fi

    MENU_KEYS=(); MENU_LABELS=()
    if [ "$installed" = false ]; then
      menu_add install  "Install OpenLegacy Hub"
      menu_add load     "Load images from a file (computer without internet)"
      menu_add save     "Save the images to a file (for a computer without internet)"
    else
      menu_add status   "Status - is everything running?"
      menu_add creds    "Passwords and addresses"
      menu_add open     "Open the Hub in the browser"
      menu_add add      "Add apps"
      menu_add remove   "Remove apps"
      if [ "$running" = true ]; then menu_add stop "Stop everything"; else menu_add start "Start everything"; fi
      menu_add restart  "Restart (everything or one part)"
      menu_add logs     "Watch the logs"
      menu_add install  "Install again: apply changed settings, upgrade or repair"
      menu_add license  "Replace the licence"
      menu_add trust    "Trust the certificate on this computer (no browser warnings)"
      menu_add save     "Save the images to a file (for a computer without internet)"
      menu_add uninst   "Uninstall (keep the data)"
      menu_add purge    "Uninstall and DELETE all data (start over from the beginning)"
    fi
    menu_add help "Help: every command"
    i=0
    while [ $i -lt ${#MENU_KEYS[@]} ]; do printf '  %2d) %s\n' $((i + 1)) "${MENU_LABELS[$i]}"; i=$((i + 1)); done
    printf '   0) Exit\n\n'

    ask_read choice "What do you want to do? Type a number: " || exit 0
    choice=$(first_number "$choice")
    [ "$choice" = 0 ] && exit 0
    case $choice in ''|*[!0-9]*) echo "Please type one of the numbers."; continue ;; esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#MENU_KEYS[@]} ]; then echo "There is no number $choice."; continue; fi
    key=${MENU_KEYS[$((choice - 1))]}

    case $key in
      install) menu_run install ;;
      status)  menu_run status ;;
      creds)   menu_run credentials ;;
      open)    open_url "$hub_url"; info "Opening $hub_url"; sleep 1 ;;
      add)     menu_add_apps ;;
      remove)  menu_remove_apps ;;
      start)   menu_run start ;;
      stop)    menu_run stop ;;
      restart) if s=$(menu_pick_service "Restart what?"); then menu_run restart $s; else echo "Not a number from the list."; fi ;;
      logs)    if s=$(menu_pick_service "Logs of what?"); then
                 info "Ctrl+C stops watching and brings you back here"; menu_run logs $s
               else echo "Not a number from the list."; fi ;;
      license) f=""; if [ -f "$ROOT/master-license.jwt" ]; then f=master-license.jwt; fi
               f=$(menu_ask_file "Licence file" "$f" || true)
               if [ -n "$f" ]; then menu_run activate-license "$f"; fi ;;
      trust)   menu_run trust-certificate ;;
      save)    f=$(menu_ask_file "File to write" "ol-hub-images.tar" || true); if [ -n "$f" ]; then menu_run save-images "$f"; fi ;;
      load)    f=$(menu_ask_file "Images file (made with \"Save the images\")" "ol-hub-images.tar" || true)
               if [ -n "$f" ]; then menu_run load-images "$f"; fi ;;
      uninst)  menu_run uninstall ;;
      purge)   menu_run uninstall --purge ;;
      help)    show_help; ask_read __x "Press Enter to return to the menu " || exit 0 ;;
    esac
  done
}
