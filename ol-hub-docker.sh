#!/usr/bin/env bash
# OpenLegacy Hub on Docker Compose - installer and day-to-day tool.
# ./ol-hub-docker.sh help  lists every command (see show_help below).
#
# Install order: postgres -> keycloak (realm ol-hub) -> ol-hub-migrate -> ol-hub -> tenant row + admin user ->
#                optional apps -> ol-hub again with every app that answers switched on -> master licence.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
# Git Bash on Windows: run without its "pseudo console". With it, every Windows program the installer starts
# (docker.exe, curl.exe) may redraw lines on the screen and leave terminal replies in the keyboard input, so
# a typed "y" arrives as garbage. The setting is read when bash starts, hence the restart.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*) case " ${MSYS:-} " in *" disable_pcon "*) ;; *) MSYS="${MSYS:+$MSYS }disable_pcon" exec bash "$0" "$@" ;; esac ;;
esac
set -eo pipefail
# Git Bash on Windows: hand /paths to docker unchanged
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
# no "What's next" adverts from the docker CLI in the middle of the installer's output
export DOCKER_CLI_HINTS=false

CALLER_DIR=$(pwd)
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
CONF_FILE="$ROOT/install.conf"
ASSUME_YES=false; PURGE=false; CMD=""; CMD_ARGS=""

. "$ROOT/lib/common.sh"
. "$ROOT/lib/secrets.sh"
. "$ROOT/lib/docker.sh"
. "$ROOT/lib/keycloak.sh"
. "$ROOT/lib/tenant.sh"
. "$ROOT/lib/credentials.sh"
. "$ROOT/lib/picklist.sh"
. "$ROOT/lib/menu.sh"

show_help() {
  cat <<EOF
${C_BOLD}OpenLegacy Hub on Docker${C_RESET} - install and run OpenLegacy Hub on this computer.

${C_BOLD}Usage:${C_RESET}  ./ol-hub-docker.sh [command] [options]
        (Windows: double-click ol-hub-docker.cmd, or  ol-hub-docker.cmd [command])

${C_BOLD}Start here${C_RESET}
  (no command)        A menu of everything below; choose by number.

${C_BOLD}Install${C_RESET}
  install             Install. Run again to apply changed settings, upgrade or repair.
                      The first time it asks 4 questions and saves the answers in install.conf.
  add APP...          Add apps, e.g.:  add ol-spec ol-coreiq
  remove APP...       Remove apps (data kept). With --purge their data is deleted too.
  activate-license F  Add or replace the master licence, e.g.:  activate-license master-license.jwt

${C_BOLD}Every day${C_RESET}
  status              Is everything running and answering? Licence, addresses.
  credentials         Passwords and addresses; save them in an encrypted file.
  stop | start        Stop everything (data kept) / start it again.
  restart [SERVICE]   Restart everything, or one part, e.g.:  restart ol-hub
  logs [SERVICE]      Watch the logs (Ctrl+C stops), e.g.:  logs ol-hub

${C_BOLD}Without internet${C_RESET}
  save-images [FILE]  With internet: put all images in one file (default ol-hub-images.tar).
  load-images FILE    Without internet: load that file, then install as usual.

${C_BOLD}Other${C_RESET}
  trust-certificate   Make this computer's browsers trust the certificate (no warnings).
  sync-keycloak       Re-apply the sign-in settings (after changing addresses).
  uninstall           Remove the containers. The data is kept; install brings it back.
  uninstall --purge   Remove everything (ALL data, passwords, install.conf) and start over.
  help                This list.

${C_BOLD}Options${C_RESET}
  -y                  Answer "yes" to every question (for scripts; needs install.conf).
  -c FILE             Use another settings file instead of install.conf.
  --purge             With remove / uninstall: delete the data too.

${C_BOLD}Apps${C_RESET} (for add / remove)
  $(printf '%s ' $APP_ORDER)

${C_BOLD}Services${C_RESET} (for restart / logs)
  proxy postgres keycloak ol-hub ol-hub-migrate and the apps above

More: README.md (Troubleshooting at the end)
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    -c) [ $# -ge 2 ] || die "-c needs a file"; CONF_FILE=$(abs_path "$2") || die "folder of '$2' not found"; shift ;;
    -y|--yes) ASSUME_YES=true ;;
    --purge) PURGE=true ;;
    -h|--help|help) show_help; exit 0 ;;
    menu|install|add|remove|status|credentials|start|stop|restart|logs|activate-license|create-tenant|sync-keycloak|trust-certificate|uninstall|save-images|load-images)
      CMD=$1 ;;
    -*) show_help; echo; die "Unknown option '$1'" ;;
    *) CMD_ARGS="$CMD_ARGS $1" ;;
  esac
  shift
done
CMD_ARGS=$(trim "$CMD_ARGS")
# Only these commands take names after them; anything else is a typo, not an install
case $CMD in
  add|remove|restart|logs|activate-license|create-tenant|save-images|load-images) ;;
  *) if [ -n "$CMD_ARGS" ]; then show_help; echo; die "Unknown command '$CMD_ARGS'"; fi ;;
esac
# No command: the menu for a person at the terminal, the install for scripts (-y, no terminal)
if [ -z "$CMD" ]; then if interactive; then CMD=menu; else CMD=install; fi; fi

# ---- checks ---------------------------------------------------------------------------------------------
preflight() {
  section "Checking this computer"
  command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Desktop (Windows, macOS) or Docker Engine (Linux): https://docs.docker.com/get-docker/"
  local err
  if ! err=$(docker info --format '{{.ServerVersion}}' 2>&1); then
    case $err in
      *"permission denied"*) die "Docker refuses this user. Run: sudo usermod -aG docker \$USER  then log out and in again (or run ./ol-hub-docker.sh with sudo)" ;;
    esac
    die "Docker is installed but not running. Start Docker Desktop (or: sudo systemctl start docker) and run ./ol-hub-docker.sh again."
  fi
  local v major minor
  v=$(docker compose version --short 2>/dev/null | tr -d '\r v' || true)
  [ -n "$v" ] || die "Docker Compose v2 is missing (the 'docker compose' command). Update Docker Desktop, or install the docker-compose-plugin package."
  major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
  if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 20 ]; }; then
    die "Docker Compose $v is too old - 2.20 or newer is needed (update Docker Desktop / docker-compose-plugin)"
  fi
  command -v curl >/dev/null 2>&1 \
    || die "curl is missing (it activates the licence). Install it: sudo apt install curl  /  sudo dnf install curl"
  local mem
  mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null | tr -d '\r' || echo 0)
  DOCKER_MEM_MB=$(( ${mem:-0} / 1048576 ))
  info "Docker $err, Compose $v, $(mb_to_gb "$DOCKER_MEM_MB") GB memory for containers"
}

# Memory the chosen apps need, against what Docker has. Before anything is downloaded.
check_memory() {   # check_memory "<apps>"
  local need a
  need=$(( $(core_mem_mb) + 1024 ))      # + room for start-up peaks
  for a in $1; do need=$(( need + $(app_mem_mb "$a") )); done
  if [ "${DOCKER_MEM_MB:-0}" -ge "$need" ]; then
    info "Memory:              $(mb_to_gb "$need") GB needed, Docker has $(mb_to_gb "$DOCKER_MEM_MB") GB"
    return 0
  fi
  warn "Docker has $(mb_to_gb "$DOCKER_MEM_MB") GB of memory; the Hub with these apps needs about $(mb_to_gb "$need") GB."
  warn "Give Docker more memory (Docker Desktop: Settings > Resources > Memory) or choose fewer apps (APPS in install.conf)."
  if interactive; then
    yes_no "Continue anyway (things may be slow or stop)?" n || stop_here
  fi
}

# Can this computer reach the image registries? A warning only: Docker may use its own proxy settings.
check_network() {
  [ "$PULL_IMAGES" = true ] || return 0
  local reg code bad=""
  mkdir -p "$ROOT/generated"
  for reg in public.ecr.aws registry-1.docker.io; do
    # a relative output file: Git Bash's curl is a Windows program and does not know /dev/null
    code=$(curl -sk -o generated/.netcheck -w '%{http_code}' --max-time 15 "https://$reg/v2/" 2>/dev/null || true)
    case $code in 2*|401) ;; *) bad="$bad $reg" ;; esac
  done
  rm -f "$ROOT/generated/.netcheck"
  [ -n "$bad" ] || { info "Image registries:    reachable"; return 0; }
  warn "This computer cannot reach:$bad - downloading the images will probably fail."
  warn "Check the internet connection; behind a company proxy, set it in Docker Desktop (Settings > Resources > Proxies)."
  warn "Without internet: on another computer run ./ol-hub-docker.sh save-images, copy the file here, then ./ol-hub-docker.sh load-images <file>."
  if interactive; then
    yes_no "Try anyway?" n || stop_here
  fi
}

show_plan() {
  section "Plan"
  info "Hub (sign in here):  $PUBLIC_HUB_URL"
  info "Keycloak:            $PUBLIC_KEYCLOAK_URL/auth"
  info "Database:            $([ "$BUNDLED_DB" = true ] && echo 'PostgreSQL 17 in Docker' || echo "external $DB_HOST:$DB_PORT/$DB_NAME")"
  info "Certificate:         $TLS_MODE"
  info "Licence:             $(basename "$MASTER_LICENSE_FILE")"
  read_license
  echo
  app_checklist "$SELECTED_APPS"
}

# Files the compose project needs (.env, generated/hub-apps.env) from the settings
prepare() {
  spin "generating passwords and keys (first time only)" ensure_secrets || exit 1
  load_kv_file "$SECRETS_FILE"
  write_env
  [ -f "$HUB_APPS_FILE" ] || write_hub_switches ""
}

pull_images() {
  if [ "$PULL_IMAGES" != true ]; then info "PULL_IMAGES=false - using the images already on this computer"; return 0; fi
  local out imgs n
  imgs=$(dc config --images "$@" 2>/dev/null | tr -d '\r' | sort -u)
  n=$(printf '%s\n' "$imgs" | grep -c . || true)
  info "Downloading $n images (several GB the first time, then only what changed)"
  if out=$(spin "downloading $n images" dc pull --quiet "$@"); then ok "images up to date"; return 0; fi
  case $out in
    *"authorization token has expired"*|*"Reauthenticate"*)
      # An old "docker login public.ecr.aws" whose token expired makes Docker refuse even public images
      info "Docker has an old login for public.ecr.aws that has expired. The images are public, so they are"
      info "downloaded without it (to remove that old login for good: docker logout public.ecr.aws)."
      if pull_anonymous $imgs; then ok "images up to date"; return 0; fi ;;
  esac
  printf '%s\n' "$out" | grep -v '^\s*$' | tail -n 5 | sed 's/^/    /' >&2
  die "Could not download the images (see above). Check the internet connection or the company proxy (Docker Desktop: Settings > Resources > Proxies), then re-run ./ol-hub-docker.sh. Without internet: ./ol-hub-docker.sh save-images on another computer, then load-images here."
}

# Pull images with an empty Docker configuration (no stored logins), to the same Docker engine
pull_anonymous() {   # pull_anonymous <image>...
  local cfg="$ROOT/generated/docker-anonymous" host img i=0 n=$#
  host=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null | tr -d '\r' || true)}
  [ -n "$host" ] || return 1
  mkdir -p "$cfg"; printf '{}\n' > "$cfg/config.json"
  command -v cygpath >/dev/null 2>&1 && cfg=$(cygpath -w "$cfg")
  for img in "$@"; do
    i=$((i + 1))
    DOCKER_CONFIG=$cfg DOCKER_HOST=$host spin "downloading ($i/$n) ${img##*/}" docker pull -q "$img" >/dev/null || return 1
    ok "  ($i/$n) ${img##*/}"
  done
}

# Images of the core and the given apps (from images.conf / install.conf)
images_for() {   # images_for "<apps>"
  local v a
  for v in IMAGE_PROXY IMAGE_POSTGRES IMAGE_KEYCLOAK IMAGE_HUB; do eval "printf '%s\n' \"\${$v}\""; done
  for a in $1; do v=$(image_var "$a"); eval "printf '%s\n' \"\${$v}\""; done
}

# Apps (from a list) that answer right now and have a switch in the Hub
ready_hub_apps() {
  local out="" a
  for a in $1; do
    in_list "$a" $APPS_IN_HUB || continue
    if answers "$a"; then out="$out $a"; fi
  done
  trim "$out"
}

# Write the Hub switches for the apps that answer; recreate the Hub when they changed
hub_switch() {   # hub_switch "<apps that should be on>"
  local on; on=$(ready_hub_apps "$1")
  local a
  for a in $1; do
    in_list "$a" $APPS_IN_HUB || continue
    in_list "$a" $on || warn "$a does not answer yet - left switched off in the Hub (re-run ./ol-hub-docker.sh when it does)"
  done
  write_hub_switches "$on"
  compose_up --no-deps ol-hub
  wait_answer ol-hub || die "the Hub did not come back (./ol-hub-docker.sh logs ol-hub)"
  ok "switched on in the Hub: ${on:-<none>}"
}

# Start the apps one after the other in APP_ORDER: each one must answer before the next one starts.
# DataIQ and its batch worker (START_TOGETHER) start together.
start_apps() {   # start_apps "<apps>"
  local a b group failed="" done_list=""
  for a in $APP_ORDER; do
    in_list "$a" $1 || continue
    in_list "$a" $done_list && continue
    group=$a
    if in_list "$a" $START_TOGETHER; then
      group=""
      for b in $START_TOGETHER; do if in_list "$b" $1; then group="$group $b"; fi; done
      group=$(trim "$group")
    fi
    for b in $group; do
      if app_has_volumes "$b"; then
        spin "preparing the data folders of $(app_name "$b")" dc run --rm --no-deps -T "$b-volumes" >/dev/null \
          || die "could not prepare the data folders of $b"
      fi
    done
    compose_up --no-deps $group
    for b in $group; do wait_answer "$b" || failed="$failed $b"; done_list="$done_list $b"; done
  done
  failed=$(trim "$failed")
  [ -z "$failed" ] || warn "not answering: $(app_names "$failed") - they stay switched off in the Hub. Check ./ol-hub-docker.sh logs <app>, then re-run ./ol-hub-docker.sh"
}

# ---- install --------------------------------------------------------------------------------------------
do_install() {
  preflight
  load_config
  first_run_questions
  require_license     # no licence, no install
  finalize_config
  show_plan
  check_memory "$SELECTED_APPS"
  check_network
  confirm "Start the installation?" || stop_here
  local n_apps; n_apps=$(printf '%s\n' $SELECTED_APPS | grep -c . || true)
  case $n_apps in
    0) ok "Installing OpenLegacy Hub (no apps)" ;;
    1) ok "Installing OpenLegacy Hub and 1 app" ;;
    *) ok "Installing OpenLegacy Hub and $n_apps apps" ;;
  esac

  section "1/6 Preparing settings and secrets"
  prepare
  ok "settings written (.env, generated/)"

  section "2/6 Images"
  pull_images

  section "3/6 HTTPS proxy and database"
  compose_up proxy
  ok "proxy listens on port $HTTPS_PORT"
  if [ "$BUNDLED_DB" = true ]; then
    compose_up postgres
    wait_healthy postgres
  else
    info "external database $DB_HOST:$DB_PORT/$DB_NAME"
  fi
  db_prepare

  section "4/6 Keycloak"
  compose_up keycloak
  wait_healthy keycloak

  section "5/6 OpenLegacy Hub"
  # apps that already answer stay switched on; new ones are switched on in step 6
  write_hub_switches "$(ready_hub_apps "$INSTALLED_APPS")"
  info "database migration, then the Hub (a few minutes the first time)"
  compose_up ol-hub
  ok "migration done"
  wait_answer ol-hub || die "the Hub did not start (./ol-hub-docker.sh logs ol-hub)"
  spin "writing the tenant" seed_tenant || exit 1      # before any app: OL-Integration seeds its admin for every ACTIVE tenant at boot
  spin "configuring the sign-in (Keycloak)" keycloak_sync || exit 1    # hub-spa redirect URIs, admin user ol-hub and its role
  spin "activating the licence" activate_license || exit 1 # now, not at the end: a licence the Hub refuses stops the install before the apps start

  section "6/6 Apps"
  if [ -n "$SELECTED_APPS" ]; then
    start_apps "$SELECTED_APPS"
    section "Switching the apps on in the Hub"
    hub_switch "$SELECTED_APPS"
  else
    info "no optional apps selected (add some later: ./ol-hub-docker.sh add <app>)"
    [ -z "$(hub_switched_on)" ] || hub_switch ""
  fi

  set_conf APPS "$SELECTED_APPS"
  [ "$TLS_MODE" != selfsigned ] || export_root_ca >/dev/null 2>&1 || true
  summary
  finish_offers
}

# After the install (only when someone sits at the terminal): the encrypted credentials file, trusting the
# certificate, opening the Hub
finish_offers() {
  interactive || { info "Passwords and addresses: ./ol-hub-docker.sh credentials"; return 0; }
  if [ ! -f "$CRED_FILE" ]; then
    printf '  %sSave the passwords%s: every password and address goes into one encrypted file,\n' "$C_BOLD" "$C_RESET"
    echo "  $(basename "$CRED_FILE") in this folder."
    save_cred_file
    echo
  elif yes_no "  Update the encrypted passwords file ($(basename "$CRED_FILE"))?" n; then
    save_cred_file
    echo
  fi
  if [ "$TLS_MODE" = selfsigned ] && ! certificate_trusted; then
    echo "  Browsers warn about the certificate until this computer trusts it, and the Hub cannot show"
    echo "  OL Terminal and OL Code until then."
    if yes_no "  Trust the certificate on this computer now?" y; then
      trust_certificate || warn "Not trusted - run ./ol-hub-docker.sh trust-certificate later, or accept the browser warning."
    fi
    echo
  fi
  if yes_no "  Open the Hub in your browser now?" y; then open_url "$PUBLIC_HUB_URL"; fi
}

open_url() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) cmd.exe /c start "" "$1" >/dev/null 2>&1 && return 0 ;;
    Darwin) open "$1" >/dev/null 2>&1 && return 0 ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then (cd /mnt/c 2>/dev/null; cmd.exe /c start "" "$1" >/dev/null 2>&1) && return 0
      elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 & return 0; fi ;;
  esac
  info "Open $1 in your browser"
}

# ---- add / remove ---------------------------------------------------------------------------------------
require_installed() {
  [ -n "$(cid ol-hub)" ] && [ -f "$ENV_FILE" ] || die "OpenLegacy Hub is not installed here yet - run ./ol-hub-docker.sh first"
}

do_add() {
  [ -n "$CMD_ARGS" ] || die "usage: ./ol-hub-docker.sh add <app> [<app>...]   (available: $APP_ORDER)"
  preflight
  load_config
  finalize_config
  require_installed
  resolve_apps "$INSTALLED_APPS $CMD_ARGS"
  local new="" a
  for a in $SELECTED_APPS; do in_list "$a" $INSTALLED_APPS || new="$new $a"; done
  new=$(trim "$new")
  [ -n "$new" ] || { ok "already installed: $CMD_ARGS"; return 0; }
  section "Add"
  info "New:        $(app_names "$new")"
  info "Installed:  $(app_names "$INSTALLED_APPS")"
  check_memory "$SELECTED_APPS"
  check_network
  confirm "Add these apps?" || stop_here
  prepare
  local svc=""
  for a in $new; do
    svc="$svc $a"
    if app_has_volumes "$a"; then svc="$svc $a-volumes"; fi
  done
  section "Images"
  pull_images $svc
  section "Apps"
  start_apps "$new"
  section "Switching the apps on in the Hub"
  hub_switch "$SELECTED_APPS"
  set_conf APPS "$SELECTED_APPS"
  summary
  if interactive && [ -f "$CRED_FILE" ]; then
    if yes_no "  Update the encrypted passwords file with the new apps?" y; then save_cred_file; fi
  fi
}

remove_containers() {   # remove the containers of a service (any profile)
  local ids
  ids=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=$1" 2>/dev/null | tr -d '\r' || true)
  [ -z "$ids" ] || docker rm -f $ids >/dev/null
}

do_remove() {
  [ -n "$CMD_ARGS" ] || die "usage: ./ol-hub-docker.sh remove <app> [<app>...]"
  preflight
  load_config
  finalize_config
  require_installed
  local gone="" keep="" a d
  for a in $CMD_ARGS; do
    a=$(canonical_app "$(lower "$a")")
    in_list "$a" $INSTALLED_APPS || die "'$a' is not installed (installed: ${INSTALLED_APPS:-<none>})"
    gone="$gone $a"
  done
  for a in $INSTALLED_APPS; do in_list "$a" $gone || keep="$keep $a"; done
  for a in $keep; do
    for d in $(app_deps "$a"); do
      if in_list "$d" $gone; then die "'$a' needs '$d' - remove '$a' too, or keep '$d'"; fi
    done
  done
  gone=$(trim "$gone"); keep=$(trim "$keep")
  section "Remove"
  info "Removing:   $gone"
  info "Keeping:    ${keep:-<none>}"
  [ "$PURGE" = true ] && warn "--purge: the data of $gone is deleted for good"
  confirm "Remove these apps?" || stop_here
  SELECTED_APPS=$keep
  prepare
  section "Switching the apps off in the Hub"
  hub_switch "$keep"
  section "Removing"
  for a in $gone; do
    remove_containers "$a"; remove_containers "$a-volumes"
    ok "removed $a"
    if [ "$PURGE" = true ] && app_has_volumes "$a"; then
      for d in $(app_volumes "$a"); do docker volume rm "${PROJECT}_$d" >/dev/null 2>&1 || true; done
      ok "$a: its files deleted (its tables stay in the shared database)"
    fi
  done
  set_conf APPS "$keep"
  [ "$PURGE" = true ] || info "Their data is kept: ./ol-hub-docker.sh add <app> brings them back with it"
}

# ---- day 2 ----------------------------------------------------------------------------------------------
load_installed() {   # settings of an existing install, without questions
  load_config
  finalize_config
  [ -f "$ENV_FILE" ] || die "OpenLegacy Hub is not installed here yet - run ./ol-hub-docker.sh first"
  load_kv_file "$SECRETS_FILE"
  load_kv_file "$ENV_FILE"
}

summary() {
  section "Done"
  cat <<EOF

  Open ${C_BOLD}$PUBLIC_HUB_URL${C_RESET} and sign in:
      user      $HUB_ADMIN_USER
      password  $(secret HUB_ADMIN_PASSWORD)

  Keycloak admin console:  $PUBLIC_KEYCLOAK_URL/auth/admin   (user $(secret KEYCLOAK_ADMIN_USER), password: ./ol-hub-docker.sh credentials)
EOF
  local a
  if [ -n "$SELECTED_APPS" ]; then
    printf '\n  The apps (after you sign in to the Hub):\n'
    for a in $SELECTED_APPS; do
      case $a in
        ol-dataiq-batch) printf '    %-15s %s\n' "DataIQ batch" "$PUBLIC_OL_DATAIQ_BATCH_URL  (DataIQ's \"View job\" links)" ;;
        ol-code)         printf '    %-15s %s\n' "OL Code" "$PUBLIC_HUB_URL/ol-code  (on its own: $PUBLIC_OL_CODE_URL)" ;;
        ol-coreiq)       printf '    %-15s %s\n' "CoreIQ" "$PUBLIC_HUB_URL/ol-coreiq  (admin panel: /ol-coreiq/admin)" ;;
        *)               printf '    %-15s %s\n' "$(app_name "$a")" "$PUBLIC_HUB_URL/$a" ;;
      esac
    done
  fi
  if [ "$TLS_MODE" = selfsigned ] && ! interactive && ! certificate_trusted; then
    cat <<EOF

  The certificate is self-signed, so the browser warns the first time. To make the warning go away (and let
  the Hub load OL Terminal / OL Code from their own addresses), run once:  ./ol-hub-docker.sh trust-certificate
EOF
  fi
  case $APPS_DOMAIN in
    localhost|*.localhost) printf '\n  These addresses work on this computer only (Chrome, Edge or Firefox).\n' ;;
    *.nip.io) printf '\n  The addresses use nip.io: the computers that open them need internet DNS.\n' ;;
    *) printf '\n  Your DNS (or each computer'"'"'s hosts file) must point these names at this computer:\n    %s\n' "$(public_hosts)" ;;
  esac
  printf '\n  Check:  ./ol-hub-docker.sh status      Passwords:  ./ol-hub-docker.sh credentials\n\n'
}

do_status() {
  load_installed
  section "Containers"
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}' 2>/dev/null || dc ps -a
  section "Answering"
  local a on
  if ! in_list "$(health_status proxy)" running healthy; then
    warn "the proxy is not running - start everything with ./ol-hub-docker.sh start"
  else
    printf '  %-18s %s\n' keycloak "$(health_status keycloak)"
    for a in ol-hub $SELECTED_APPS; do
      if answers "$a"; then printf '  %-18s %sOK%s\n' "$a" "$C_GREEN" "$C_RESET"
      else printf '  %-18s %snot answering%s (%s)\n' "$a" "$C_RED" "$C_RESET" "$(container_state "$a")"; fi
    done
    on=$(hub_switched_on)
    section "Apps in the Hub (through the gateway)"
    [ -n "$on" ] || printf '  none switched on\n'
    local p
    for a in $on; do
      p=$(hub_remote_path "$a")
      case $a in
        ol-terminal)    printf '  %-18s switched on (the browser loads it from %s)\n' "$a" "$PUBLIC_OL_TERMINAL_URL"; continue ;;
        ol-integration) printf '  %-18s switched on (/backend, designer)\n' "$a"; continue ;;
      esac
      if probe "http://ol-hub:8080$p"; then printf '  %-18s %sOK%s  %s\n' "$a" "$C_GREEN" "$C_RESET" "$p"
      else printf '  %-18s %sFAIL%s %s\n' "$a" "$C_RED" "$C_RESET" "$p"; fi
    done
  fi
  section "Tenant and licence"
  if [ "$BUNDLED_DB" != true ] || [ "$(health_status postgres)" = healthy ]; then
    local row; row=$(tenant_license)
    if [ -z "$row" ]; then printf '  no tenant yet (./ol-hub-docker.sh activate-license <file>)\n'
    elif [ "${row%%|*}" = none ]; then printf '  tenant %s: %sno licence%s (./ol-hub-docker.sh activate-license <file>)\n' "$(tenant_id_target)" "$C_YELLOW" "$C_RESET"
    else printf '  tenant %s: licence %s, expires %s\n' "$(tenant_id_target)" "${row%%|*}" "${row#*|}"; fi
  else
    printf '  database not running\n'
  fi
  section "Addresses"
  printf '  Hub:       %s\n  Keycloak:  %s/auth/admin\n' "$PUBLIC_HUB_URL" "$PUBLIC_KEYCLOAK_URL"
}

do_credentials() {
  load_installed
  if interactive; then credentials_menu; return 0; fi
  # no terminal (scripts): everything
  section "Passwords and addresses"
  cred_all | sed 's/^/  /'
  printf '  All of them are in secrets.env (keep it safe, and back it up with the data).\n'
}

do_start() {
  load_installed
  section "Starting"
  compose_up
  wait_answer ol-hub || die "the Hub did not start (./ol-hub-docker.sh logs ol-hub)"
  local a; for a in $SELECTED_APPS; do wait_answer "$a" || true; done
  ok "OpenLegacy Hub is running: $PUBLIC_HUB_URL"
}

do_stop() {
  load_installed
  section "Stopping"
  spin "stopping" dc stop >/dev/null || die "could not stop everything (./ol-hub-docker.sh status)"
  ok "stopped (data kept). Start again with ./ol-hub-docker.sh start"
}

do_restart() {
  load_installed
  spin "restarting ${CMD_ARGS:-everything}" dc restart $CMD_ARGS >/dev/null || die "restart failed (./ol-hub-docker.sh status)"
  ok "restarted ${CMD_ARGS:-everything}"
}

do_logs() {
  [ -f "$ENV_FILE" ] || die "OpenLegacy Hub is not installed here yet - run ./ol-hub-docker.sh first"
  info "Ctrl+C stops following the logs (the services keep running)"
  dc logs -f --tail 200 $CMD_ARGS
}

do_activate_license() {
  load_config
  finalize_config
  require_installed
  if [ -n "$CMD_ARGS" ]; then
    local f; f=$(abs_path "$CMD_ARGS" || true)
    check_license "$f" || die "$LIC_ERR"
    keep_license_file "$f"
  else
    require_license
  fi
  load_kv_file "$SECRETS_FILE"; load_kv_file "$ENV_FILE"
  wait_answer ol-hub 60 || die "the Hub is not running - ./ol-hub-docker.sh start"
  spin "writing the tenant" seed_tenant || exit 1
  spin "configuring the sign-in (Keycloak)" keycloak_sync || exit 1
  spin "activating the licence" activate_license || exit 1
}

do_sync_keycloak() {
  load_installed
  spin "configuring the sign-in (Keycloak)" keycloak_sync || exit 1
}

# The proxy's local certificate authority -> certs/openlegacy-root-ca.crt
export_root_ca() {
  local f="$ROOT/certs/openlegacy-root-ca.crt" i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    dc exec -T proxy test -f /data/caddy/pki/authorities/local/root.crt 2>/dev/null && break
    sleep 2
  done
  dc exec -T proxy cat /data/caddy/pki/authorities/local/root.crt > "$f.tmp" 2>/dev/null && [ -s "$f.tmp" ] \
    || { rm -f "$f.tmp"; return 1; }
  tr -d '\r' < "$f.tmp" > "$f"; rm -f "$f.tmp"
  echo "$f"
}

# ---- offline image bundle -------------------------------------------------------------------------------
# save-images: on a computer with internet, download the images and write them to one file.
# load-images: on the computer without internet, load that file; the installer then uses those images.
do_save_images() {
  preflight
  load_config
  [ "$APPS" != __unset__ ] || APPS=""
  local file apps imgs img
  file=${CMD_ARGS:-ol-hub-images.tar}
  case $file in /*|[A-Za-z]:*) ;; *) file="$CALLER_DIR/$file" ;; esac
  if [ -n "$(trim "$APPS")" ]; then resolve_apps "$APPS"; apps=$SELECTED_APPS
  else apps=$APP_ORDER; info "No APPS in install.conf: saving the images of every app"; fi
  imgs=$(images_for "$apps" | sort -u)
  section "Downloading $(printf '%s\n' "$imgs" | grep -c .) images (core + $(app_names "$apps"))"
  for img in $imgs; do
    info "  $img"
    spin "downloading $img" docker pull -q "$img" >/dev/null 2>&1 || pull_anonymous "$img" || die "could not download $img"
  done
  section "Writing $file"
  info "this can take several minutes (about 1 GB per image)"
  spin "writing $(basename "$file")" docker save -o "$(native_file "$file")" $imgs || die "could not write $file"
  ok "saved: $file ($(du -h "$file" 2>/dev/null | cut -f1))"
  info "Copy it, together with this folder, to the other computer and run there:  ./ol-hub-docker.sh load-images $(basename "$file")"
}

do_load_images() {
  [ -n "$CMD_ARGS" ] || die "usage: ./ol-hub-docker.sh load-images <file made by save-images>"
  preflight
  local file; file=$(abs_path "$CMD_ARGS" || true)
  [ -f "$file" ] || die "File '$CMD_ARGS' not found"
  section "Loading images from $(basename "$file")"
  info "this can take several minutes"
  spin "loading $(basename "$file")" docker load -i "$(native_file "$file")" || die "could not load $file"
  load_config
  set_conf PULL_IMAGES false
  ok "images loaded; install.conf now has PULL_IMAGES=false. Run ./ol-hub-docker.sh to install."
}

# A file path for docker.exe on Windows (C:\...), unchanged elsewhere
native_file() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

TRUST_MARKER="$ROOT/generated/certificate-trusted"

# Has this computer already trusted this installation's certificate authority? (remembered by checksum)
certificate_trusted() {
  local f; f=$(export_root_ca 2>/dev/null) || return 1
  [ -f "$TRUST_MARKER" ] && [ "$(cksum < "$f")" = "$(cat "$TRUST_MARKER")" ]
}

# Add the installation's certificate authority to this computer's trusted certificates. 0 = done.
trust_certificate() {
  local f; f=$(export_root_ca) || { warn "the proxy has not made its certificate yet - is it running? (./ol-hub-docker.sh start)"; return 1; }
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      info "Windows now asks whether to install the certificate: click Yes."
      certutil -user -addstore Root "$(cygpath -w "$f")" >/dev/null || { warn "Windows did not add it (was Yes clicked?)"; return 1; }
      ok "trusted for your Windows user (Edge, Chrome). Restart the browser if it is open." ;;
    Darwin)
      info "macOS now asks for your password to change your keychain."
      security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$f" \
        || { warn "macOS did not add it"; return 1; }
      ok "trusted in your login keychain (Safari, Chrome, Edge). Restart the browser if it is open." ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null && command -v certutil.exe >/dev/null 2>&1; then
        info "Windows now asks whether to install the certificate: click Yes."
        certutil.exe -user -addstore Root "$(wslpath -w "$f")" >/dev/null || { warn "Windows did not add it"; return 1; }
        ok "trusted for your Windows user (Edge, Chrome). Restart the browser if it is open."
      elif [ -d /usr/local/share/ca-certificates ] && command -v update-ca-certificates >/dev/null 2>&1; then
        info "Adding it to this Linux system (sudo may ask for your password)."
        { sudo cp "$f" /usr/local/share/ca-certificates/openlegacy-root-ca.crt && sudo update-ca-certificates >/dev/null; } \
          || { warn "could not add it (sudo needed)"; return 1; }
        ok "trusted by this Linux system"
        info "Chrome and Firefox on Linux keep their own list: import $f in the browser (certificate settings > Authorities)."
      else
        info "Import $f as a trusted authority in your browser's certificate settings."; return 1
      fi ;;
    *) info "Import $f as a trusted root certificate on this computer."; return 1 ;;
  esac
  info "Firefox keeps its own list: Settings > Privacy & Security > Certificates > View Certificates > Authorities > Import"
  mkdir -p "$(dirname "$TRUST_MARKER")"; cksum < "$f" > "$TRUST_MARKER"
}

do_trust_certificate() {
  load_installed
  [ "$TLS_MODE" = selfsigned ] || die "TLS_MODE is $TLS_MODE - only the self-signed certificate needs this"
  section "Trust the certificate"
  info "Trusting it lets this computer's browsers open the OpenLegacy addresses without a warning."
  confirm "Add it to the trusted certificates of this computer?" || { info "Not changed (README: Certificates)."; return 0; }
  trust_certificate || die "the certificate was not added"
}

do_uninstall() {
  load_config
  section "Uninstall"
  if [ "$PURGE" = true ]; then
    warn "This deletes ALL OpenLegacy data on this computer - the database, every app's files, the passwords"
    warn "(secrets.env, ol-hub-credentials.enc) and your answers (install.conf) - and starts over from the beginning."
    warn "Your licence file is kept."
    warn "This cannot be undone."
    if [ "$ASSUME_YES" != true ]; then
      interactive || die "--purge needs a terminal to confirm (or -y)"
      local a; ask_read a "Type DELETE to delete everything: " || true
      [ "$a" = DELETE ] || stop_here
    fi
  else
    info "Removes the containers. The data (database, app files) and secrets.env are kept: ./ol-hub-docker.sh brings it all back."
    confirm "Remove the OpenLegacy containers?" || stop_here
  fi
  if [ -f "$ENV_FILE" ]; then
    COMPOSE_PROFILES='*' spin "removing the containers" dc down --remove-orphans >/dev/null || true
  fi
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null | tr -d '\r' || true)
  [ -z "$ids" ] || docker rm -f $ids >/dev/null
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  ok "containers removed"
  if [ "$PURGE" = true ]; then
    local v
    for v in $(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null | tr -d '\r'); do
      if docker volume rm "$v" >/dev/null; then ok "deleted volume $v"; else warn "could not delete volume $v"; fi
    done
    rm -f "$ENV_FILE" "$SECRETS_FILE" "$CRED_FILE" "$ROOT/certs/openlegacy-root-ca.crt" "$CONF_FILE" "$ROOT/master-license.jwt.previous"
    rm -rf "$ROOT/generated"
    ok "everything deleted - the next install starts from the beginning (the questions come again)"
  fi
}

on_exit() {
  local rc=$? j
  tty_restore    # the terminal as it was (typing shown again), also after an error or Ctrl+C
  for j in $(jobs -p); do kill "$j" 2>/dev/null || true; done   # a step still running with a spinner
  rm -f "$ROOT/generated/.spin.$$."* 2>/dev/null || true
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 130 ]; then printf '\n%sStopped (Ctrl+C).%s Re-running ./ol-hub-docker.sh is safe.\n' "$C_YELLOW" "$C_RESET" >&2; return 0; fi
  case $CMD in install|add|remove|activate-license|create-tenant) ;; *) return 0 ;; esac
  printf '\n%sThe %s step stopped with an error.%s Re-running ./ol-hub-docker.sh is safe.\n' "$C_RED" "$CMD" "$C_RESET" >&2
  printf 'Help: ./ol-hub-docker.sh status   ./ol-hub-docker.sh logs <service>   README.md > Troubleshooting\n' >&2
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 129' HUP TERM
if interactive; then
  set_title "OpenLegacy Hub"
  keys_quiet
fi

case $CMD in
  install)           do_install ;;
  add)               do_add ;;
  remove)            do_remove ;;
  status)            do_status ;;
  credentials)       do_credentials ;;
  start)             do_start ;;
  stop)              do_stop ;;
  restart)           do_restart ;;
  logs)              do_logs ;;
  activate-license|create-tenant) do_activate_license ;;
  sync-keycloak)     do_sync_keycloak ;;
  trust-certificate) do_trust_certificate ;;
  menu)              do_menu ;;
  uninstall)         do_uninstall ;;
  save-images)       do_save_images ;;
  load-images)       do_load_images ;;
esac
