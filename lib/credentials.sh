#!/usr/bin/env bash
# Credentials: show them (the user picks which), save them in an encrypted file, open that file again.
#
# The encrypted file is ol-hub-credentials.enc: AES-256 with a key derived from the user's password (PBKDF2,
# 200000 rounds), base64 text. Without this script it opens with:
#   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -a -in ol-hub-credentials.enc
# secrets.env stays the source of every password (docker compose reads it); the encrypted file is a copy that
# can be kept or sent somewhere safe.

CRED_FILE="$ROOT/ol-hub-credentials.enc"
CRED_HEADER="OpenLegacy Hub - credentials"
ENC_ARGS="-aes-256-cbc -pbkdf2 -iter 200000 -a"

# One block per kind of credential; prints nothing when it does not apply (app not installed, external DB)
cred_block() {   # cred_block <hub|keycloak|coreiq|atomiq|api|database>
  case $1 in
    hub) cat <<EOF
OpenLegacy Hub - sign in here. Every app in the Hub uses this same sign-in.
    address   $PUBLIC_HUB_URL
    user      $HUB_ADMIN_USER
    password  $(secret HUB_ADMIN_PASSWORD)
EOF
    ;;
    keycloak) cat <<EOF
Keycloak admin console - for administrators only (users, sign-in settings).
    address   $PUBLIC_KEYCLOAK_URL/auth/admin
    user      $(secret KEYCLOAK_ADMIN_USER)
    password  $(secret KEYCLOAK_ADMIN_PASSWORD)
EOF
    ;;
    coreiq) in_list ol-coreiq $SELECTED_APPS || return 0; cat <<EOF
CoreIQ admin panel - sign in to the Hub first; the panel asks for this passkey.
    address   $PUBLIC_HUB_URL/ol-coreiq/admin
    passkey   $(secret COREIQ_ADMIN_PASSKEY)
EOF
    ;;
    atomiq) in_list ol-atomiq $SELECTED_APPS || return 0; cat <<EOF
AtomIQ admin passkey - for AtomIQ's admin functions (sign in to the Hub first).
    address   $PUBLIC_HUB_URL/ol-atomiq
    passkey   $(secret ATOMIQ_ADMIN_PASSKEY)
EOF
    ;;
    api)
      in_list ol-code $SELECTED_APPS || in_list ol-terminal $SELECTED_APPS || in_list ol-coreiq $SELECTED_APPS || return 0
      echo "App API admin accounts (technical) - not for the browser. Each app has its own admin account for"
      echo "its admin API (/api/v1/admin/...); the installer generates a different password for each."
      if in_list ol-code $SELECTED_APPS; then
        printf '    %-12s user %-8s password %s\n' "OL Code" "$(secret OL_CODE_ADMIN | grep . || echo openlegacy)" "$(secret OL_CODE_PASSWORD)"; fi
      if in_list ol-terminal $SELECTED_APPS; then
        printf '    %-12s user %-8s password %s\n' "OL Terminal" "$(secret OL_TERMINAL_ADMIN)" "$(secret OL_TERMINAL_PASSWORD)"; fi
      if in_list ol-coreiq $SELECTED_APPS; then
        printf '    %-12s user %-8s password %s\n' "CoreIQ" "$(secret COREIQ_ADMIN)" "$(secret COREIQ_PASSWORD)"; fi
    ;;
    database) [ "$BUNDLED_DB" = true ] || return 0; cat <<EOF
PostgreSQL database - only reachable inside Docker (docker compose exec postgres psql -U $DB_USER).
    database  $DB_NAME
    user      $DB_USER
    password  $(secret OL_DB_PASSWORD)
EOF
    ;;
  esac
}
cred_label() {
  case $1 in
    hub)      echo "OpenLegacy Hub - sign in here (all apps use this sign-in)" ;;
    keycloak) echo "Keycloak admin console (administrators)" ;;
    coreiq)   echo "CoreIQ admin panel passkey" ;;
    atomiq)   echo "AtomIQ admin passkey" ;;
    api)      echo "App API admin accounts (technical)" ;;
    database) echo "PostgreSQL database" ;;
  esac
}
CRED_KINDS="hub keycloak coreiq atomiq api database"

cred_all() {
  local k out
  for k in $CRED_KINDS; do
    out=$(cred_block "$k")
    if [ -n "$out" ]; then printf '%s\n\n' "$out"; fi
  done
}

# openssl enc with this computer's openssl, else the one in the PostgreSQL image. Password in $OLHUB_FILE_PW.
run_openssl_enc() {   # run_openssl_enc [-d]   (stdin -> stdout)
  local input; input=$(cat)
  if command -v openssl >/dev/null 2>&1 \
     && printf '%s\n' "$input" | openssl enc "$@" $ENC_ARGS -pass env:OLHUB_FILE_PW 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$input" | docker run --rm -i -e OLHUB_FILE_PW --entrypoint openssl "$IMAGE_POSTGRES" \
    enc "$@" $ENC_ARGS -pass env:OLHUB_FILE_PW 2>/dev/null
}

# Ask for a new password (twice) and write every credential to the encrypted file. Enter = skip.
save_cred_file() {
  local pw pw2 plain
  echo "  The file is protected with a password you choose now. Keep that password safe:"
  echo "  without it the file cannot be opened."
  while :; do
    flush_input; read -r -s -p "  Password for the file (at least 8 characters, Enter = skip): " pw || pw=""; echo
    if [ -z "$pw" ]; then info "Not saved. Later: ./ol-hub-docker.sh credentials, then \"Save\"."; return 0; fi
    if [ ${#pw} -lt 8 ]; then echo "  At least 8 characters, please."; continue; fi
    read -r -s -p "  The same password again: " pw2 || pw2=""; echo
    [ "$pw" = "$pw2" ] && break
    echo "  The two passwords are different. Again, please."
  done
  plain=$(printf '%s (saved %s)\n\n%s\n' "$CRED_HEADER" "$(date '+%Y-%m-%d %H:%M')" "$(cred_all)")
  export OLHUB_FILE_PW=$pw
  if printf '%s\n' "$plain" | run_openssl_enc > "$CRED_FILE.tmp" && [ -s "$CRED_FILE.tmp" ]; then
    mv "$CRED_FILE.tmp" "$CRED_FILE"; chmod 600 "$CRED_FILE" 2>/dev/null || true
    ok "saved: $(basename "$CRED_FILE") in this folder (encrypted)"
  else
    rm -f "$CRED_FILE.tmp"; warn "could not encrypt the file (openssl missing, and Docker could not run it)"
  fi
  unset OLHUB_FILE_PW pw pw2 plain
}

# Ask for the file's password and show what is inside
open_cred_file() {
  local pw plain
  [ -f "$CRED_FILE" ] || { warn "There is no encrypted file yet (choose \"Save\" first)."; return 0; }
  flush_input; read -r -s -p "  Password of $(basename "$CRED_FILE"): " pw || pw=""; echo
  export OLHUB_FILE_PW=$pw
  plain=$(run_openssl_enc -d < "$CRED_FILE" | tr -d '\000' || true)
  unset OLHUB_FILE_PW pw
  case $plain in
    "$CRED_HEADER"*) echo; printf '%s\n' "$plain" | sed 's/^/  /' ;;
    *) warn "Wrong password (or the file is damaged)." ;;
  esac
}

# The credentials menu: the user picks what to see by number
credentials_menu() {
  local keys="" k i choice n
  for k in $CRED_KINDS; do if [ -n "$(cred_block "$k")" ]; then keys="$keys $k"; fi; done
  keys="$keys all save"
  [ -f "$CRED_FILE" ] && keys="$keys open"
  while :; do
    section "Passwords and addresses"
    echo "Which credentials do you want to see?"
    i=1
    for k in $keys; do
      case $k in
        all)  printf '  %2d) %s\n' $i "All of the above" ;;
        save) if [ -f "$CRED_FILE" ]; then printf '  %2d) %s\n' $i "Update the encrypted file ($(basename "$CRED_FILE"))"
              else printf '  %2d) %s\n' $i "Save all of them in an encrypted file"; fi ;;
        open) printf '  %2d) %s\n' $i "Open the encrypted file ($(basename "$CRED_FILE"))" ;;
        *)    printf '  %2d) %s\n' $i "$(cred_label "$k")" ;;
      esac
      i=$((i + 1))
    done
    printf '   0) Back\n'
    ask_read choice "Choose a number: " || return 0
    choice=$(first_number "$choice")
    [ "$choice" = 0 ] && return 0
    case $choice in ''|*[!0-9]*) echo "Please type one of the numbers."; continue ;; esac
    k=$(printf '%s\n' $keys | sed -n "${choice}p")
    [ -n "$k" ] || { echo "There is no number $choice."; continue; }
    echo
    case $k in
      all)  cred_all | sed 's/^/  /' ;;
      save) save_cred_file
            if [ -f "$CRED_FILE" ] && ! in_list open $keys; then keys="$keys open"; fi ;;
      open) open_cred_file ;;
      *)    cred_block "$k" | sed 's/^/  /' ;;
    esac
    echo
    ask_read n "Press Enter to continue " || return 0
  done
}
