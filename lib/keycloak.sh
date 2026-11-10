#!/usr/bin/env bash
# Keycloak realm ol-hub, kept in sync on every run with kcadm inside the Keycloak container (it logs in with
# the container's own bootstrap-admin variables; no password is passed on a command line):
#   - hub-spa redirect URIs: the Hub address, every app address, EXTRA_REDIRECT_URIS (URIs added by hand in
#     the admin console are kept). Web origins are "+" in the realm template already.
#   - the built-in admin: user "ol-hub" with the fixed id 9a780e8b... (seeded as admin by the Hub and
#     OL-Integration), linked to the tenant (ol-tenantId, ol-company), password from secrets.env
#   - its admin role rows in the database
# The realm template (config/keycloak/realm-ol-hub.json) already enables unmanaged user attributes, without
# which Keycloak drops ol-tenantId / ol-company / ol-fullname.

# Container-side prelude: log in with a fresh per-call config (a cached session expires), then
# $K <subcommand> ... runs kcadm with it. (kcadm only accepts --config after the subcommand.)
KC_PRELUDE='
  C=$(mktemp /tmp/kcadm.XXXXXX); trap "rm -f $C" EXIT
  kc() { /opt/keycloak/bin/kcadm.sh "$@" --config "$C"; }
  /opt/keycloak/bin/kcadm.sh config credentials --config "$C" --server http://localhost:8080/auth \
    --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1 \
    || { echo "kcadm login failed (Keycloak admin from secrets.env: KEYCLOAK_ADMIN_USER / KEYCLOAK_ADMIN_PASSWORD)" >&2; exit 1; }
  K=kc
'
kc_exec() {   # kc_exec '$K get ...'  (stdin is passed through)
  dc exec -T keycloak bash -c "$KC_PRELUDE$1" | tr -d '\r'
}

# hub-spa must allow every address a browser opens (the Hub, and the apps with their own address)
required_redirects() {
  printf '%s\n' "$PUBLIC_HUB_URL/*" "$PUBLIC_OL_CODE_URL/*" "$PUBLIC_OL_TERMINAL_URL/*" "$PUBLIC_OL_DATAIQ_BATCH_URL/*"
  printf '%s\n' "$EXTRA_REDIRECT_URIS" | tr ' \t' '\n\n'
}

keycloak_sync() {
  section "Keycloak realm ol-hub"
  [ "$(health_status keycloak)" = healthy ] || wait_healthy keycloak

  # 1. hub-spa redirect URIs (union: existing ones are kept)
  local cid_ existing all json u
  cid_=$(kc_exec '$K get clients -r ol-hub -q clientId=hub-spa --fields id --format csv --noquotes' | sed -n 1p || true)
  [ -n "$cid_" ] || die "client hub-spa not found in realm ol-hub (./ol-hub-docker.sh logs keycloak)"
  existing=$(kc_exec "\$K get clients/$cid_ -r ol-hub --fields redirectUris" | tr -d '\n' \
              | sed -n 's/.*"redirectUris" *: *\[\([^]]*\)\].*/\1/p' | grep -o '"[^"]*"' | tr -d '"' || true)
  all=$( { printf '%s\n' "$existing"; required_redirects; } | grep -v -e '^$' -e '\${' -e '__' | awk '!seen[$0]++' || true)
  json="["
  while IFS= read -r u; do if [ -n "$u" ]; then json="$json\"$u\","; fi; done <<EOF
$all
EOF
  json="${json%,}]"
  printf '%s\n' "$json" | kc_exec "read -r J; \$K update clients/$cid_ -r ol-hub -s \"redirectUris=\$J\"" >/dev/null \
    || die "could not update the hub-spa redirect URIs"
  ok "hub-spa redirect URIs: $(printf '%s' "$all" | tr '\n' ' ')"

  # 2. the built-in admin: realm user "ol-hub" with the fixed id HUB_ADMIN_ID. Created by partial import, the
  #    only admin API that keeps a given id. On a re-run an existing user is left as it is (its password may
  #    have been changed since).
  local tid org
  tid=${CONF_TENANT_ID:-$DEFAULT_TENANT_ID}
  org=$TENANT_ORGANIZATION
  if kc_exec "\$K get users/$HUB_ADMIN_ID -r ol-hub --fields id" >/dev/null 2>&1; then
    ok "user '$HUB_ADMIN_USER' exists"
  else
    local email=null
    [ -n "$HUB_ADMIN_EMAIL" ] && email="\"$HUB_ADMIN_EMAIL\""
    printf '%s' "{\"ifResourceExists\":\"SKIP\",\"users\":[{\"id\":\"$HUB_ADMIN_ID\",\"username\":\"$HUB_ADMIN_USER\",\"email\":$email,\"enabled\":true,\"emailVerified\":true,\"firstName\":\"ol\",\"lastName\":\"hub\",\"attributes\":{\"ol-tenantId\":[\"$tid\"],\"ol-company\":[\"$org\"],\"ol-fullname\":[\"ol-hub\"]},\"realmRoles\":[\"uma_authorization\",\"offline_access\"],\"clientRoles\":{\"account\":[\"manage-account\",\"view-profile\"]}}]}" \
      | kc_exec '$K create partialImport -r ol-hub -f -' >/dev/null || true
    kc_exec "\$K get users/$HUB_ADMIN_ID -r ol-hub --fields id" >/dev/null 2>&1 \
      || die "could not create user '$HUB_ADMIN_USER' (id $HUB_ADMIN_ID). Is there another user named '$HUB_ADMIN_USER' or with the e-mail '$HUB_ADMIN_EMAIL'? Delete it in the Keycloak admin console and re-run."
    printf '%s\n' "$(secret HUB_ADMIN_PASSWORD)" \
      | kc_exec "read -r PW; \$K set-password -r ol-hub --userid $HUB_ADMIN_ID --new-password \"\$PW\"" >/dev/null \
      || die "could not set the password of user '$HUB_ADMIN_USER'"
    ok "user '$HUB_ADMIN_USER'${HUB_ADMIN_EMAIL:+ <$HUB_ADMIN_EMAIL>} created, tenant $tid ($org)"
  fi

  # 3. admin role rows (normally seeded already for the default tenant; added for any other TENANT_ID).
  #    Without them every backoffice / licence call answers 503 "Could not resolve the tenant role".
  local ds="data_$(printf '%s' "$tid" | tr '-' '_')"
  psql_c "INSERT INTO auth.tenant_user_role (tenant_id, user_id, role) VALUES ('$tid', '$HUB_ADMIN_ID', 'admin') ON CONFLICT (tenant_id, user_id) DO NOTHING;
DO \$\$ BEGIN
  IF to_regclass('$ds.user_role') IS NOT NULL THEN
    INSERT INTO $ds.user_role (user_id, role) SELECT '$HUB_ADMIN_ID', 'admin'
    WHERE NOT EXISTS (SELECT 1 FROM $ds.user_role WHERE user_id = '$HUB_ADMIN_ID');
  END IF;
END \$\$;" >/dev/null || die "could not write the admin role of user '$HUB_ADMIN_USER'"
  ok "user '$HUB_ADMIN_USER' is admin of tenant $tid"
}
