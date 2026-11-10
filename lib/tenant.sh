#!/usr/bin/env bash
# Tenant + master licence:
#
# 1. seed_tenant - always. A fresh Hub creates no tenant (and no route creates one), so the installer inserts
#    the ACTIVE operational.tenant row by SQL, right after the Hub migration. Default id: the built-in tenant
#    4a6bfc5d... whose admin (Keycloak user ol-hub, 9a780e8b...) OL-Integration seeds in data_<tenant> at boot,
#    so the row must exist before OL-Integration first starts.
#
# 2. activate_license - the master licence (required). It is activated through the Hub, not by SQL:
#    PUT /backoffice/api/v1/tenants/<id>/license {"license": "<JWT>"} as the admin ol-hub (the shell's licence
#    screen calls the same route). The Hub verifies the signature, refuses expired or non-MASTER licences and
#    stores it. Runs after the apps are up, when the admin role resolves.
#    The calls go from this computer to the proxy (curl --resolve <host>:<port>:127.0.0.1), so no DNS is needed.

tenant_id_target() { echo "${CONF_TENANT_ID:-$DEFAULT_TENANT_ID}"; }

b64url_decode() {
  local s; s=$(tr '_-' '/+')
  while [ $((${#s} % 4)) -ne 0 ]; do s="$s="; done
  printf '%s' "$s" | base64 -d 2>/dev/null || printf '%s' "$s" | base64 -D 2>/dev/null
}
json_str() { printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2\" *: *\"\([^\"]*\)\".*/\1/p"; }
json_num() { printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2\" *: *\([0-9][0-9]*\).*/\1/p"; }

# Check a licence file locally. 0 = usable (LIC_JWT, LIC_ID, LIC_EXP, LIC_GRACE set); 1 = not (LIC_ERR says why).
check_license() {
  local file=$1 payload f
  LIC_ERR=""
  [ -f "$file" ] || { LIC_ERR="File not found: $file"; return 1; }
  LIC_JWT=$(tr -d ' \r\n\t' < "$file")
  printf '%s' "$LIC_JWT" | grep -Eq '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' \
    || { LIC_ERR="$file is not a licence key (it should be the .jwt file from OpenLegacy)"; return 1; }
  payload=$(printf '%s' "$LIC_JWT" | cut -d. -f2 | b64url_decode || true)
  [ -n "$payload" ] || { LIC_ERR="The licence in $file cannot be read (is the file complete?)"; return 1; }
  printf '%s' "$payload" | grep -Eq '"licenseType" *: *"MASTER"' \
    || { LIC_ERR="$file is not a master licence. Ask OpenLegacy for the master-licence key."; return 1; }
  for f in masterLicenseId expirationDate gracePeriodDays tenantId issueDate; do
    printf '%s' "$payload" | grep -q "\"$f\"" || { LIC_ERR="The licence in $file has no $f - ask OpenLegacy for a new one"; return 1; }
  done
  LIC_ID=$(json_str "$payload" masterLicenseId)
  LIC_EXP=$(json_str "$payload" expirationDate); LIC_GRACE=$(json_num "$payload" gracePeriodDays)
  return 0
}

# Check MASTER_LICENSE_FILE (stops on a bad file) and show what it is
read_license() {
  check_license "$MASTER_LICENSE_FILE" || die "$LIC_ERR"
  info "licence $LIC_ID: expires ${LIC_EXP:-?}, grace period ${LIC_GRACE:-?} days"
  case $LIC_EXP in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*)
      if [ "$(printf '%s' "$LIC_EXP" | cut -c1-10)" \< "$(date -u +%Y-%m-%d)" ]; then
        warn "the licence expired on $LIC_EXP - the Hub accepts it only within its ${LIC_GRACE:-?}-day grace period"
      fi ;;
  esac
}

# Keep the licence in this folder as master-license.jwt, so re-runs and upgrades always find it
keep_license_file() {   # keep_license_file <file>
  local dest="$ROOT/master-license.jwt"
  if [ "$1" != "$dest" ]; then
    if [ -f "$dest" ] && ! cmp -s "$1" "$dest"; then mv "$dest" "$dest.previous"; fi
    cp "$1" "$dest"
    [ "${QUIET_LICENSE:-false}" = true ] || info "licence copied to master-license.jwt in this folder"
  fi
  chmod 600 "$dest" 2>/dev/null || true
  MASTER_LICENSE_FILE=$dest
  # during the first questions install.conf does not exist yet: they save it when all are answered
  if [ "${CONF_EXISTS:-true}" = true ]; then set_conf MASTER_LICENSE_FILE ./master-license.jwt; fi
}

# Ask for the licence file until a usable one is given (3 empty answers: stop)
ask_license() {
  interactive || die "A master licence is required: put the .jwt file from OpenLegacy in this folder as master-license.jwt and run again."
  local def="" f empty=0 found
  if [ -f "$ROOT/master-license.jwt" ]; then def=./master-license.jwt
  else
    found=$(cd "$ROOT" && ls -1 ./*.jwt 2>/dev/null || true)
    [ "$(printf '%s\n' "$found" | grep -c .)" = 1 ] && def=$found
  fi
  echo "     The .jwt file you received from OpenLegacy. Easiest: copy it into this"
  echo "     folder first. You can also type its full path, or drag the file in here."
  echo
  while :; do
    ask f "     Licence file" "$def"
    f=$(printf '%s' "$f" | sed "s/^[\"']//; s/[\"']\$//")
    if [ -z "$f" ]; then
      empty=$((empty + 1))
      [ "$empty" -lt 3 ] || die "The installation needs the master licence. Ask OpenLegacy for it, then run ./ol-hub-docker.sh again."
      echo "     The installation cannot start without the licence file."
      continue
    fi
    if [ "$f" = "$def" ]; then f="$ROOT/${f#./}"; else f=$(abs_path "$f" || true); fi
    if check_license "$f"; then break; fi
    echo "     $LIC_ERR"
  done
  printf '     %sOK%s  master licence, valid until %s\n' "$C_GREEN" "$C_RESET" "${LIC_EXP%%T*}"
  QUIET_LICENSE=true keep_license_file "$f"
}

# The installer does not start without a usable licence
require_license() {
  local f=$MASTER_LICENSE_FILE
  if [ -z "$f" ] && [ -f "$ROOT/master-license.jwt" ]; then f="$ROOT/master-license.jwt"; fi
  if [ -n "$f" ]; then
    f=$(native_path "$f")
    case $f in /*|[A-Za-z]:*) ;; *) f="$(cd "$(dirname "$CONF_FILE")" && pwd)/${f#./}" ;; esac
    if check_license "$f"; then keep_license_file "$f"; return 0; fi
    warn "$LIC_ERR"
  else
    warn "No master licence yet (MASTER_LICENSE_FILE in install.conf)."
  fi
  section "Master licence (required)"
  ask_license
}

# 1. The ACTIVE tenant row (idempotent)
seed_tenant() {
  section "Tenant"
  local tid contact st
  tid=$(tenant_id_target)
  contact=${TENANT_CONTACT:-$HUB_ADMIN_USER}
  psql_stdin -v "tid=$tid" -v "org=$TENANT_ORGANIZATION" -v "contact=$contact" >/dev/null <<'SQL' \
    || die "could not write the tenant (did the Hub migration run? ./ol-hub-docker.sh logs ol-hub-migrate)"
INSERT INTO operational.tenant (id, organization, contact_person, created_at, status, update_status_at, update_at)
VALUES (:'tid'::uuid, :'org', :'contact', now(), 'ACTIVE', now(), now())
ON CONFLICT (id) DO NOTHING;
SQL
  st=$(psql_c "SELECT status FROM operational.tenant WHERE id = '$tid';" | sed -n 1p || true)
  [ -n "$st" ] || die "tenant $tid was not written"
  [ "$st" = ACTIVE ] || warn "tenant $tid exists with status $st (not ACTIVE) - left as it is"
  ok "tenant $tid ($st, $TENANT_ORGANIZATION)"
}

# Licence state of the tenant -> "<licence id>|<expiry>" or "" (used by status)
tenant_license() {
  psql_c "SELECT coalesce(m.id::text,'none') || '|' || coalesce(to_char(m.expiration_date AT TIME ZONE 'UTC','YYYY-MM-DD'),'') FROM operational.tenant t LEFT JOIN operational.master_license m ON m.id = t.master_license_id WHERE t.id = '$(tenant_id_target)';" 2>/dev/null | sed -n 1p || true
}

curl_hub() {   # curl with the public host names resolved to this computer (no DNS needed)
  curl -sk --max-time 60 \
    --resolve "$HUB_HOST:$HTTPS_PORT:127.0.0.1" --resolve "$KEYCLOAK_HOST:$HTTPS_PORT:127.0.0.1" "$@"
}

# Admin token for user ol-hub (hub-spa password grant) -> stdout. Never printed by callers.
admin_token() {
  printf "%s" "$(secret HUB_ADMIN_PASSWORD)" | curl_hub -d grant_type=password -d client_id=hub-spa -d "username=$HUB_ADMIN_USER" \
    --data-urlencode "password@-" "$PUBLIC_KEYCLOAK_URL/auth/realms/ol-hub/protocol/openid-connect/token" \
    | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p' || true
}

# 2. Licence activation through the Hub (idempotent)
activate_license() {
  if [ -z "$MASTER_LICENSE_FILE" ]; then
    warn "No licence file (MASTER_LICENSE_FILE) - the Hub runs without a licence. Add it later: ./ol-hub-docker.sh activate-license <file>"
    return 0
  fi
  section "Master licence"
  read_license
  local tid owner linked tmp tok code i msg row
  tid=$(tenant_id_target)

  # One licence, one tenant
  owner=$(psql_c "SELECT tenant_id FROM operational.master_license WHERE id = '$LIC_ID';" | sed -n 1p || true)
  if [ -n "$owner" ] && [ "$owner" != "$tid" ]; then
    die "licence $LIC_ID is already used by tenant $owner - a tenant needs its own licence (or set TENANT_ID=$owner)"
  fi
  # Already active for this tenant: nothing to do (no admin login needed)
  linked=$(psql_c "SELECT to_char(m.expiration_date AT TIME ZONE 'UTC','YYYY-MM-DD') FROM operational.tenant t JOIN operational.master_license m ON m.id = t.master_license_id WHERE t.id = '$tid' AND m.id = '$LIC_ID';" | sed -n 1p || true)
  if [ -n "$linked" ]; then
    ok "licence $LIC_ID is already active (expires $linked)"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl is not installed here: activate the licence in the Hub instead (sign in as $HUB_ADMIN_USER, licence screen, paste the contents of $MASTER_LICENSE_FILE)"
    return 0
  fi
  # relative path inside this folder: Git Bash's curl is a Windows program and cannot open /tmp paths
  tmp="generated/licence-$$"; rm -rf "$tmp"; mkdir -p "$tmp"; chmod 700 "$tmp" 2>/dev/null || true
  printf '{"license":"%s"}' "$LIC_JWT" > "$tmp/body.json"
  for i in 1 2 3 4 5 6; do   # the admin role may take a moment to resolve right after the apps start
    tok=$(admin_token)
    if [ -z "$tok" ]; then
      [ "$i" -lt 6 ] && { info "  no sign-in token from $PUBLIC_KEYCLOAK_URL yet - retrying in 10s ($i/6)"; sleep 10; continue; }
      rm -rf "$tmp"; die "user '$HUB_ADMIN_USER' cannot sign in at $PUBLIC_KEYCLOAK_URL (./ol-hub-docker.sh sync-keycloak, then ./ol-hub-docker.sh activate-license)"
    fi
    printf 'Authorization: Bearer %s\n' "$tok" > "$tmp/auth.hdr"
    code=$(curl_hub -o "$tmp/out.json" -w '%{http_code}' -X PUT -H @"$tmp/auth.hdr" -H 'Content-Type: application/json' \
      --data-binary @"$tmp/body.json" "$PUBLIC_HUB_URL/backoffice/api/v1/tenants/$tid/license" || true)
    rm -f "$tmp/auth.hdr"
    case $code in 2*) break ;; 503|000|502|504) ;; *) break ;; esac   # 4xx: refused for good
    info "  the Hub answered $code - retrying in 10s ($i/6)"; sleep 10
  done
  unset tok
  if [ "${code#2}" = "$code" ]; then
    msg=$(json_str "$(cat "$tmp/out.json" 2>/dev/null)" detailedMessage)
    [ -n "$msg" ] || msg=$(json_str "$(cat "$tmp/out.json" 2>/dev/null)" message)
    msg=$(printf '%s' "$msg" | cut -c1-300)
    rm -rf "$tmp"
    die "the Hub refused the licence: HTTP $code${msg:+ - $msg}. $([ "$CMD" = install ] && echo "The apps were not started. ")Check the licence file with OpenLegacy (a master licence for this installation), then run ./ol-hub-docker.sh again."
  fi
  rm -rf "$tmp"

  row=$(tenant_license)
  [ "${row%%|*}" = "$LIC_ID" ] || die "the Hub accepted the licence but tenant $tid is linked to '${row%%|*}'"
  ok "licence $LIC_ID activated (expires ${row#*|})"
}
