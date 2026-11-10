#!/usr/bin/env bash
# Shared helpers: logging, questions, the app catalog, configuration and host names.
# Written for bash 3.2+ (the bash that ships with macOS), so no associative arrays or ${x,,}.

C_RESET=$'\033[0m'; C_BLUE=$'\033[1;36m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[0;31m'
C_BOLD=$'\033[1m'
# OpenLegacy orange (#E96B0F): exact where the terminal says it has 24-bit colour, else the nearest of 256
case "${COLORTERM:-}" in
  truecolor|24bit) C_ORANGE=$'\033[38;2;233;107;15m' ;;
  *)               C_ORANGE=$'\033[38;5;166m' ;;
esac
[ -t 1 ] || { C_RESET=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=; C_BOLD=; C_ORANGE=; }

# The terminal window's title (most terminals: Git Bash, Windows Terminal, macOS Terminal, Linux)
set_title() { [ -t 1 ] && printf '\033]0;%s\007' "$1"; return 0; }

# The OL Hub mark - an orange cube - with the title, "Docker installer", and two status lines
ol_banner() {   # ol_banner "<status>" ["<second status line>"]
  local o=$C_ORANGE r=$C_RESET
  printf '\n%s      ____%s\n' "$o" "$r"
  printf '%s     /\\   \\%s      %sOpenLegacy Hub%s\n' "$o" "$r" "$C_BOLD" "$r"
  printf '%s    /  \\___\\%s     Docker installer\n' "$o" "$r"
  printf '%s    \\  /   /%s     %s\n' "$o" "$r" "$1"
  printf '%s     \\/___/%s      %s\n\n' "$o" "$r" "${2:-}"
}

log()     { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*"; }
info()    { log "${C_BLUE}INFO${C_RESET}  $*"; }
ok()      { log "${C_GREEN}OK${C_RESET}    $*"; }
warn()    { log "${C_YELLOW}WARN${C_RESET}  $*" >&2; }
die()     { log "${C_RED}ERROR${C_RESET} $*" >&2; exit 1; }
section() { printf '\n%s== %s ==%s\n' "$C_BLUE" "$*" "$C_RESET"; }

interactive() { [ -t 0 ] && [ -t 1 ] && [ "${ASSUME_YES:-false}" != true ]; }

# ---- spinner: shown on the terminal while the installer waits ----------------------------------------------
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) SPIN_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) ;;
  *) SPIN_CHARS=('|' '/' '-' '\') ;;
esac
SPIN_I=0
spin_on() { [ -t 2 ] && [ -n "$C_RESET" ]; }   # a terminal on stderr (the spinner never goes into captured output)
status_line() {   # redraw one status line: spinner + text
  spin_on || return 0
  SPIN_I=$(( (SPIN_I + 1) % ${#SPIN_CHARS[@]} ))
  printf '\r  %s%s%s %s\033[K' "$C_BLUE" "${SPIN_CHARS[$SPIN_I]}" "$C_RESET" "$*" >&2
}
status_clear() { spin_on && printf '\r\033[K' >&2; return 0; }
# Wait N seconds, animating the spinner with a message
spin_sleep() {   # spin_sleep <seconds> <message>
  local n=$(( $1 * 5 )) i=0
  if ! spin_on; then sleep "$1"; return 0; fi
  while [ $i -lt $n ]; do status_line "$2"; sleep 0.2; i=$((i + 1)); done
}
# Run a command (or a function) with a spinner; its output is shown when it ends, its exit code returned
spin() {   # spin "<message>" <command> [args...]
  local msg=$1; shift
  if ! spin_on; then "$@" 2>&1; return; fi
  local tmp="$ROOT/generated/.spin.$$.$RANDOM" pid rc=0 start=$SECONDS
  mkdir -p "$ROOT/generated"
  ( "$@" ) > "$tmp" 2>&1 < /dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do status_line "$msg  $((SECONDS - start))s"; sleep 0.2; done
  wait "$pid" || rc=$?
  status_clear
  cat "$tmp"; rm -f "$tmp"
  return "$rc"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim()  { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }

# Throw away keys/terminal replies that arrived before the question (bash 4+; macOS bash 3.2 does not need it)
flush_input() {
  [ -t 0 ] || return 0
  [ "${BASH_VERSINFO[0]:-3}" -ge 4 ] || return 0
  local junk
  while read -r -s -t 0.15 -n 1000 junk 2>/dev/null; do :; done
  return 0
}
# An answer without terminal control sequences and control characters (as typed)
clean_answer() { printf '%s' "$1" | sed $'s/\033\\[[0-9;?]*[A-Za-z~]//g; s/\033[]PX^_][^\a\033]*\a\\{0,1\\}//g' | tr -d '\000-\037\177'; }
# Keys pressed while the installer works are not shown: the terminal would print them in the middle of the
# output (an arrow key even moves the cursor, so later lines land in the wrong place). Questions show the
# typing while they wait; the terminal is set back as it was when the script ends.
TTY_SAVED=""
keys_quiet() { [ -t 0 ] || return 0; TTY_SAVED=$(stty -g 2>/dev/null) || { TTY_SAVED=""; return 0; }; stty -echo 2>/dev/null || true; }
keys_echo()  { [ -z "$TTY_SAVED" ] || stty echo 2>/dev/null || true; }
keys_hide()  { [ -z "$TTY_SAVED" ] || stty -echo 2>/dev/null || true; }
tty_restore() { [ -z "$TTY_SAVED" ] || stty "$TTY_SAVED" 2>/dev/null || true; }

# read with a prompt, after flushing stale input; the answer is cleaned and trimmed.
# OLHUB_DEBUG=1 records exactly what the terminal sent (generated/answers.log) - to diagnose odd terminals.
ask_read() {   # ask_read VAR "prompt"
  local __v=$1 __a="" __rc=0
  [ ! -t 1 ] || printf '\033[?1004l'   # no focus reports (ESC [ I / ESC [ O) typed into the answer
  flush_input
  keys_echo
  read -r -p "$2" __a || __rc=1
  keys_hide
  if [ -n "${OLHUB_DEBUG:-}" ]; then
    mkdir -p "$ROOT/generated"
    printf '%s  %-40.40s  raw=%q\n' "$(date '+%H:%M:%S')" "$(trim "$2")" "$__a" >> "$ROOT/generated/answers.log"
  fi
  __a=$(trim "$(clean_answer "$__a")")
  printf -v "$__v" '%s' "$__a"
  return $__rc
}
# The first number in an answer ("" if none): letters a terminal slipped in before or after it are ignored
first_number() { local w; for w in $(printf '%s' "$1" | tr -c '0-9' ' '); do printf '%s' "$w"; return 0; done; }
# y or n from an answer, "" when unclear. Every word counts, so leftovers of terminal codes before or after
# the answer (like the "O" of ESC [ O) do not hide it; an answer with both y and n is unclear.
# With the keyboard still in Hebrew the Y and N keys type ט and מ: they count as y and n (so do כן and לא).
yes_no_word() {
  local w y=false n=false s=$1
  s=${s//כן/ y }; s=${s//לא/ n }; s=${s//ט/ y }; s=${s//מ/ n }
  for w in $(lower "$s" | tr -c 'a-z0-9' ' '); do
    case $w in y|yes) y=true ;; n|no) n=true ;; esac
  done
  if [ $y = true ] && [ $n = false ]; then printf y; elif [ $n = true ] && [ $y = false ]; then printf n; fi
}
# Does an answer contain letters of another alphabet (keyboard not set to English)?
other_alphabet() { printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; }

ask() {   # ask VAR "question" "default"  (no terminal or -y: the default)
  local __var=$1 __q=$2 __def=${3:-} __ans=
  if interactive; then ask_read __ans "$__q${__def:+ [$__def]}: " || true; fi
  [ -n "$__ans" ] || __ans=$__def
  printf -v "$__var" '%s' "$__ans"
}

confirm() {   # confirm "question" -> 0 on yes (no terminal or -y: yes); asks again on an unclear answer
  [ "${ASSUME_YES:-false}" = true ] && return 0
  interactive || return 0
  yes_no "$1" n
}

# yes_no "question" default(y|n) -> 0 on yes. Asks again until the answer is y, yes, n, no or Enter.
yes_no() {
  local q=$1 def=$2 hint a
  [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
  while :; do
    ask_read a "$q $hint: " || true
    local typed=$a
    if [ -z "$a" ]; then a=$def; else a=$(yes_no_word "$a"); fi
    case $a in y) return 0 ;; n) return 1 ;; esac
    if other_alphabet "$typed"; then
      echo "     Please answer y (yes) or n (no) - the keyboard is typing another language: switch it to English (Alt+Shift)."
    else
      echo "     Please answer y (yes) or n (no)."
    fi
  done
}

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }
# The user said no: not an error
stop_here() { info "Stopped - nothing was changed"; exit 0; }

# A Windows path typed in Git Bash (C:\Users\me\licence.jwt) -> /c/Users/me/licence.jwt
native_path() {
  case $1 in
    [A-Za-z]:[\\/]*) if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; return; fi ;;
  esac
  printf '%s' "$1"
}

# A path as the user typed it (relative to the folder they ran ./ol-hub-docker.sh from) -> absolute path
abs_path() {   # prints the path as given and returns 1 when its folder does not exist
  local p d; p=$(native_path "$1")
  case $p in /*) ;; *) p="${CALLER_DIR:-$ROOT}/$p" ;; esac
  d=$(cd "$(dirname "$p")" 2>/dev/null && pwd) || { printf '%s' "$1"; return 1; }
  printf '%s/%s' "$d" "$(basename "$p")"
}
in_list() { local x=$1; shift; local i; for i in "$@"; do [ "$i" = "$x" ] && return 0; done; return 1; }

# ---- app catalog -----------------------------------------------------------------------------------------
# The built-in tenant and its admin: the Hub and OL-Integration seed (tenant 4a6bfc5d..., Keycloak user
# 9a780e8b..., admin) in their migrations. The installer adds the tenant row and the realm user with that id.
DEFAULT_TENANT_ID=4a6bfc5d-3bae-45a3-99b9-d1e255875adb
HUB_ADMIN_ID=9a780e8b-ba98-4f0c-8424-4e4cc27b1f67
HUB_ADMIN_USER=ol-hub
PROJECT=ol-hub            # compose project name (docker-compose.yml "name:")
NETWORK=ol-hub-net        # compose network name

# Install order. The apps start one after the other in this order (each must answer before the next one
# starts), OL Integration first because several apps call it. DataIQ and its batch worker start together.
APP_ORDER="ol-integration ol-termiq ol-dataiq ol-dataiq-batch ol-appiq ol-next ol-spec ol-code ol-terminal ol-coreiq ol-atomiq"
START_TOGETHER="ol-dataiq ol-dataiq-batch"
# Apps the Hub switches on in its shell / gateway (config/hub/apps/<app>.env). Inside the Hub each one is a
# page of its own: https://ol-hub.<domain>/<app>, e.g. /ol-termiq.
APPS_IN_HUB="ol-integration ol-termiq ol-dataiq ol-appiq ol-next ol-spec ol-code ol-terminal ol-coreiq ol-atomiq"
# Apps without an address of their own get one that leads to their Hub page: https://ol-termiq.<domain>
# -> https://ol-hub.<domain>/ol-termiq (OL Code, OL Terminal and DataIQ batch have real addresses of their own)
APPS_REDIRECTED="ol-integration ol-termiq ol-dataiq ol-appiq ol-next ol-spec ol-coreiq ol-atomiq"

# NAME = the name people know (name_of, no subshell); app_name prints it
name_of() {
  case $1 in
    ol-hub)          NAME="OpenLegacy Hub" ;;
    keycloak)        NAME="Keycloak" ;;
    postgres)        NAME="PostgreSQL" ;;
    proxy)           NAME="HTTPS proxy" ;;
    ol-integration)  NAME="OL Integration" ;;
    ol-dataiq-batch) NAME="DataIQ batch" ;;
    ol-termiq)       NAME="TermIQ" ;;
    ol-dataiq)       NAME="DataIQ" ;;
    ol-appiq)        NAME="AppIQ" ;;
    ol-next)         NAME="OL Next" ;;
    ol-spec)         NAME="OL Spec" ;;
    ol-code)         NAME="OL Code" ;;
    ol-terminal)     NAME="OL Terminal" ;;
    ol-coreiq)       NAME="CoreIQ" ;;
    ol-atomiq)       NAME="AtomIQ" ;;
    *)               NAME="$1" ;;
  esac
}
app_name() { name_of "$1"; printf '%s\n' "$NAME"; }
# NAMES = "A, B, C" for a list of apps ("none" when empty); app_names prints it
app_names_v() { local a out=""; for a in $1; do name_of "$a"; out="${out:+$out, }$NAME"; done; NAMES=${out:-none}; }
app_names() { app_names_v "$1"; printf '%s' "$NAMES"; }

# Every app on its own row, [x] for the ones that will be installed, with a line that says so:
#      Apps   ([x] = will be installed)
#        [x] OL Integration
#        [ ] AppIQ
app_checklist() {   # app_checklist "<chosen apps>"
  local a mark
  # Plain text only: no colour codes next to the marks, so every terminal shows them the same way
  printf '     Apps   ([x] = will be installed)\n'
  for a in $APP_ORDER; do
    mark="[ ]"
    if in_list "$a" $1; then mark="[x]"; fi
    printf '       %s %s\n' "$mark" "$(app_name "$a")"
  done
}

# The apps an app needs: DEPS (deps_of, no subshell) or printed (app_deps)
deps_of() {
  case $1 in
    ol-termiq|ol-appiq) DEPS="ol-integration" ;;
    ol-dataiq)          DEPS="ol-integration ol-dataiq-batch" ;;
    *)                  DEPS="" ;;
  esac
}
app_deps() { deps_of "$1"; [ -z "$DEPS" ] || echo "$DEPS"; }

# Memory (MB) each component needs to run comfortably (its memory request on Kubernetes). Measured idle use is
# lower; Java start-up needs the room. check_memory adds them up for the chosen apps.
core_mem_mb() { echo $(( 64 + 512 + 768 + 1024 )); }   # proxy + postgres + keycloak + hub
app_mem_mb() {
  case $1 in
    ol-integration|ol-dataiq) echo 1024 ;;
    ol-termiq|ol-appiq|ol-next|ol-spec|ol-code) echo 768 ;;
    *) echo 512 ;;
  esac
}
mb_to_gb() { awk -v m="$1" 'BEGIN { printf "%.1f", m / 1024 }'; }

# The image variable of a component: ol-dataiq-batch -> IMAGE_OL_DATAIQ_BATCH
image_var() { printf 'IMAGE_%s' "$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')"; }

# URL that answers 200 once the component is up (checked from inside the Docker network)
probe_url() {
  case $1 in
    ol-hub)          echo "http://ol-hub:8080/health" ;;
    ol-integration)  echo "http://ol-integration:8080/health" ;;
    ol-dataiq-batch) echo "http://ol-dataiq-batch:8089/actuator/health" ;;
    ol-termiq)       echo "http://ol-termiq:8094/health" ;;
    ol-dataiq)       echo "http://ol-dataiq:9092/health" ;;
    ol-appiq)        echo "http://ol-appiq:8095/health" ;;
    ol-next)         echo "http://ol-next:8080/api" ;;
    ol-spec)         echo "http://ol-spec:3008/health" ;;
    ol-code)         echo "http://ol-code:9091/health" ;;
    ol-terminal)     echo "http://ol-terminal:9093/health" ;;
    ol-coreiq)       echo "http://ol-coreiq:8090/health" ;;
    ol-atomiq)       echo "http://ol-atomiq:8091/health" ;;
  esac
}

# The app's remote through the Hub gateway (checked by "status")
hub_remote_path() {
  case $1 in
    ol-termiq)   echo /remotes/termiq/remoteEntry.json ;;
    ol-dataiq)   echo /remotes/dataiq/remoteEntry.json ;;
    ol-appiq)    echo /remotes/appiq/remoteEntry.json ;;
    ol-next)     echo /remotes/ol-next/remoteEntry.json ;;
    ol-spec)     echo /remotes/olspec/remoteEntry.json ;;
    ol-code)     echo /remotes/olcode/remoteEntry.json ;;
    ol-coreiq)   echo /remotes/ol-coreiq/remoteEntry.json ;;
    ol-atomiq)   echo /remotes/ol-atomiq/remoteEntry.json ;;
  esac
}

# Named volumes of an app (docker-compose.yml) and whether it has a <app>-volumes step
app_volumes() {
  case $1 in
    ol-dataiq)   echo "ol-dataiq-data" ;;
    ol-next)     echo "ol-next-data ol-next-cache" ;;
    ol-spec)     echo "ol-spec-data ol-spec-cache" ;;
    ol-code)     echo "ol-code-data" ;;
    ol-terminal) echo "ol-terminal-traffic ol-terminal-data" ;;
  esac
}
app_has_volumes() { [ -n "$(app_volumes "$1")" ]; }

# Short names (termiq, coreiq, ...) are accepted too
canonical_app() {
  case $1 in
    termiq) echo ol-termiq ;; dataiq) echo ol-dataiq ;; dataiq-batch) echo ol-dataiq-batch ;;
    appiq) echo ol-appiq ;; coreiq) echo ol-coreiq ;; atomiq) echo ol-atomiq ;;
    olspec) echo ol-spec ;; *) echo "$1" ;;
  esac
}

# Apps whose containers exist in this install (whatever install.conf says), in install order
installed_apps() {
  local have a out=""
  have=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
           --format '{{.Label "com.docker.compose.service"}}' 2>/dev/null | tr -d '\r' || true)
  for a in $APP_ORDER; do
    if in_list "$a" $have; then out="$out $a"; fi
  done
  trim "$out"
}

# The app list to mark -> APPS. Every app starts marked; exactly the marked apps are installed.
ask_apps() {
  local start=$APPS
  [ "$start" != __unset__ ] || start=$APP_ORDER
  pick_apps add installed "$APP_ORDER" "$start"
  QUIET_RESOLVE=true resolve_apps "$PICKED"
  APPS=$SELECTED_APPS
}

# APPS (+ the apps they need) -> SELECTED_APPS, in install order
resolve_apps() {
  local want="" a d changed=true
  for a in $1; do
    a=$(canonical_app "$(lower "$a")")
    in_list "$a" $APP_ORDER || die "Unknown app '$a'. Available: $APP_ORDER"
    in_list "$a" $want || want="$want $a"
  done
  while $changed; do
    changed=false
    for a in $want; do
      for d in $(app_deps "$a"); do
        if ! in_list "$d" $want; then
          want="$want $d"; changed=true
          [ "${QUIET_RESOLVE:-false}" = true ] || info "Adding $(app_name "$d") ($d), needed by $(app_name "$a")"
        fi
      done
    done
  done
  SELECTED_APPS=""
  for a in $APP_ORDER; do if in_list "$a" $want; then SELECTED_APPS="$SELECTED_APPS $a"; fi; done
  SELECTED_APPS=$(trim "$SELECTED_APPS")
}

# ---- configuration ----------------------------------------------------------------------------------------
# install.conf / images.conf / secrets.env are KEY=value lines; Windows line endings are fine.
load_kv_file() { [ -f "$1" ] || return 0; eval "$(tr -d '\r' < "$1")"; }

# set_conf KEY VALUE: change (or add) one line in install.conf
set_conf() {
  local key=$1 val=$2 tmp
  [ -f "$CONF_FILE" ] || cp "$ROOT/install.conf.example" "$CONF_FILE"
  tmp="$CONF_FILE.tmp.$$"
  tr -d '\r' < "$CONF_FILE" | awk -v k="$key" -v line="$key=\"$val\"" '
      index($0, k "=") == 1 && !done { print line; done = 1; next }
      { print }
      END { if (!done) print line }' > "$tmp"
  mv "$tmp" "$CONF_FILE"
}

# A value that is written into install.conf, JSON and SQL: no quotes, $, backslash or backtick
safe_text() { case $1 in *[\"\'\$\\\`]*) return 1 ;; esac; return 0; }

load_config() {
  load_kv_file "$ROOT/images.conf"
  CONF_EXISTS=false
  if [ -f "$CONF_FILE" ]; then
    load_kv_file "$CONF_FILE"; CONF_EXISTS=true
  fi
  : "${APPS_DOMAIN:=}" "${HUB_HOST:=}" "${KEYCLOAK_HOST:=}" "${OL_CODE_HOST:=}" "${OL_TERMINAL_HOST:=}"
  : "${OL_DATAIQ_BATCH_HOST:=}" "${EXTRA_REDIRECT_URIS:=}"
  : "${HTTPS_PORT:=443}" "${HTTP_PORT:=80}" "${TLS_MODE:=selfsigned}" "${ACME_EMAIL:=}"
  : "${DB_HOST:=}" "${DB_PORT:=5432}" "${DB_NAME:=postgres}" "${DB_USER:=postgres}" "${DB_PASSWORD:=}"
  : "${MASTER_LICENSE_FILE:=}" "${TENANT_ORGANIZATION:=OpenLegacy}" "${TENANT_CONTACT:=}" "${TENANT_ID:=}"
  : "${HUB_ADMIN_EMAIL=admin@openlegacy.com}"
  : "${PULL_IMAGES:=true}" "${WAIT_TIMEOUT:=900}"
  [ -n "${APPS+x}" ] || APPS=__unset__
}

# First run without install.conf: a few questions, saved to install.conf
first_run_questions() {
  [ "$CONF_EXISTS" = false ] || return 0
  if ! interactive; then
    [ "$APPS" != __unset__ ] || APPS=""
    return 0
  fi
  section "A few questions"
  echo "  Your answers are saved in install.conf; you can change them there later."

  q_heading "1. Address"
  cat <<EOF
     Every part of OpenLegacy Hub gets its own address under one domain,
     for example https://ol-hub.<domain> and https://keycloak.<domain>.
     Type one of:

       localhost        Only this computer can open the Hub. Nothing to set up.
       an IP address    Other computers can open it too, e.g. 192.168.1.20
                        (the free nip.io DNS service turns it into names).
       your domain      e.g. ol.example.com - your DNS must point
                        *.ol.example.com at this computer.

EOF
  ask APPS_DOMAIN "     Domain" "${APPS_DOMAIN:-localhost}"

  q_heading "2. Master licence (required)"
  ask_license

  q_heading "3. Apps"
  echo "     PostgreSQL, Keycloak and the Hub are always installed. Mark the apps"
  echo "     to install; exactly the marked apps are installed. You can add or"
  echo "     remove apps later."
  echo
  ask_apps

  q_heading "4. Organization"
  echo "     Your company name (it names the tenant)."
  echo
  ask TENANT_ORGANIZATION "     Organization" "$TENANT_ORGANIZATION"
  safe_text "$TENANT_ORGANIZATION" || die "The organization name must not contain quotes, \$, \\ or \`"

  # install.conf is written only now, when every question is answered: a run stopped half-way leaves no
  # install.conf behind, so the next run asks all the questions again
  set_conf APPS_DOMAIN "$APPS_DOMAIN"
  set_conf MASTER_LICENSE_FILE ./master-license.jwt
  set_conf APPS "$APPS"
  set_conf TENANT_ORGANIZATION "$TENANT_ORGANIZATION"
  CONF_EXISTS=true
  echo
  ok "Answers saved to $(basename "$CONF_FILE")"
}

q_heading() { printf '\n  %s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
# A question padded to one width, so the [y/N] answers line up
q_line() { printf '     %-50s' "$1"; }

# Validate the settings and derive everything else (host names, URLs, apps, database)
finalize_config() {
  [ "$APPS" != __unset__ ] || APPS=""

  APPS_DOMAIN=$(lower "$(trim "${APPS_DOMAIN:-localhost}")")
  [ -n "$APPS_DOMAIN" ] || APPS_DOMAIN=localhost
  if printf '%s' "$APPS_DOMAIN" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    [ "${CMD:-install}" != install ] || info "$APPS_DOMAIN is an IP address: using the host names *.$APPS_DOMAIN.nip.io (free public DNS for that IP)"
    APPS_DOMAIN="$APPS_DOMAIN.nip.io"
  fi
  printf '%s' "$APPS_DOMAIN" | grep -Eq '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$' || die "APPS_DOMAIN '$APPS_DOMAIN' is not a valid domain"
  HUB_HOST=$(lower "${HUB_HOST:-ol-hub.$APPS_DOMAIN}")
  KEYCLOAK_HOST=$(lower "${KEYCLOAK_HOST:-keycloak.$APPS_DOMAIN}")
  OL_CODE_HOST=$(lower "${OL_CODE_HOST:-ol-code.$APPS_DOMAIN}")
  OL_TERMINAL_HOST=$(lower "${OL_TERMINAL_HOST:-ol-terminal.$APPS_DOMAIN}")
  OL_DATAIQ_BATCH_HOST=$(lower "${OL_DATAIQ_BATCH_HOST:-ol-dataiq-batch.$APPS_DOMAIN}")

  case $HTTPS_PORT in ''|*[!0-9]*) die "HTTPS_PORT must be a number" ;; esac
  case $HTTP_PORT in ''|*[!0-9]*) die "HTTP_PORT must be a number" ;; esac
  [ "$HTTPS_PORT" != "$HTTP_PORT" ] || die "HTTPS_PORT and HTTP_PORT must be different"
  PUBLIC_HUB_URL=$(public_url "$HUB_HOST")
  PUBLIC_KEYCLOAK_URL=$(public_url "$KEYCLOAK_HOST")
  PUBLIC_OL_CODE_URL=$(public_url "$OL_CODE_HOST")
  PUBLIC_OL_TERMINAL_URL=$(public_url "$OL_TERMINAL_HOST")
  PUBLIC_OL_DATAIQ_BATCH_URL=$(public_url "$OL_DATAIQ_BATCH_HOST")
  # short addresses that lead to the apps' Hub pages, and which host label (from the right) is the app name
  APP_REDIRECT_URLS=""
  for a in $APPS_REDIRECTED; do APP_REDIRECT_URLS="${APP_REDIRECT_URLS:+$APP_REDIRECT_URLS, }$(public_url "$a.$APPS_DOMAIN")"; done
  APP_HOST_LABEL=$(printf '%s' "$APPS_DOMAIN" | tr -cd . | wc -c | tr -d ' '); APP_HOST_LABEL=$((APP_HOST_LABEL + 1))

  TLS_MODE=$(lower "$TLS_MODE")
  case $TLS_MODE in
    selfsigned) ;;
    custom)
      [ -f "$ROOT/certs/tls.crt" ] && [ -f "$ROOT/certs/tls.key" ] \
        || die "TLS_MODE=custom: put your certificate in certs/tls.crt and its key in certs/tls.key" ;;
    letsencrypt)
      [ -n "$ACME_EMAIL" ] || die "TLS_MODE=letsencrypt needs ACME_EMAIL (your e-mail for Let's Encrypt)"
      case $APPS_DOMAIN in localhost|*.localhost|*.nip.io) die "TLS_MODE=letsencrypt needs a real domain in APPS_DOMAIN" ;; esac ;;
    *) die "TLS_MODE must be selfsigned, custom or letsencrypt" ;;
  esac

  safe_text "$TENANT_ORGANIZATION$TENANT_CONTACT$HUB_ADMIN_EMAIL$ACME_EMAIL" \
    || die "TENANT_ORGANIZATION, TENANT_CONTACT, HUB_ADMIN_EMAIL and ACME_EMAIL must not contain quotes, \$, \\ or \`"
  if [ -n "$TENANT_ID" ]; then
    printf '%s' "$TENANT_ID" | grep -Eq '^[0-9a-fA-F-]{36}$' || die "TENANT_ID '$TENANT_ID' is not a UUID"
  fi
  CONF_TENANT_ID=$TENANT_ID
  # the licence file is checked where it is needed (install: require_license; activate-license)
  if [ -n "$MASTER_LICENSE_FILE" ]; then
    MASTER_LICENSE_FILE=$(native_path "$MASTER_LICENSE_FILE")
    case $MASTER_LICENSE_FILE in
      /*|[A-Za-z]:*) ;;
      *) MASTER_LICENSE_FILE="$(cd "$(dirname "$CONF_FILE")" && pwd)/${MASTER_LICENSE_FILE#./}" ;;
    esac
  fi

  BUNDLED_DB=true
  if [ -n "$DB_HOST" ]; then
    BUNDLED_DB=false
    [ -n "$DB_PASSWORD" ] || die "DB_PASSWORD is required with an external DB_HOST"
    case $DB_PASSWORD in *\'*) die "DB_PASSWORD must not contain a single quote (')" ;; esac
  fi
  case $WAIT_TIMEOUT in ''|*[!0-9]*) die "WAIT_TIMEOUT must be a number of seconds" ;; esac

  # Apps already installed always stay selected: a re-run never removes an app (./ol-hub-docker.sh remove does)
  INSTALLED_APPS=$(installed_apps)
  resolve_apps "$APPS $INSTALLED_APPS"
}

public_url() { if [ "$HTTPS_PORT" = 443 ]; then echo "https://$1"; else echo "https://$1:$HTTPS_PORT"; fi; }

# Any public host name under .localhost? (those need docker-compose.localhost.yml)
is_localhost_domain() {
  local h
  for h in $(public_hosts); do case $h in localhost|*.localhost) return 0 ;; esac; done
  return 1
}

# Host names of the addresses a browser opens (for the hosts file / DNS hint)
public_hosts() {
  local a out="$HUB_HOST $KEYCLOAK_HOST $OL_CODE_HOST $OL_TERMINAL_HOST $OL_DATAIQ_BATCH_HOST"
  for a in $APPS_REDIRECTED; do out="$out $a.$APPS_DOMAIN"; done
  echo "$out"
}
