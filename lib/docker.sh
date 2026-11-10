#!/usr/bin/env bash
# Docker helpers: the compose wrapper, waiting for components, probes, SQL against the shared database.

dc() { docker compose "$@"; }

# Container id of a service ("" when it has none)
cid() { docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=$1" 2>/dev/null | tr -d '\r' | sed -n 1p; }

container_state() {   # running / exited / ... + (healthy) + restarts
  local id; id=$(cid "$1")
  [ -n "$id" ] || { echo "not created"; return 0; }
  docker inspect -f '{{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}{{if gt .RestartCount 0}}, restarted {{.RestartCount}}x{{end}}' "$id" 2>/dev/null | tr -d '\r'
}

health_status() {
  local id; id=$(cid "$1")
  [ -n "$id" ] || { echo none; return 0; }
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null | tr -d '\r'
}

# HTTP check from inside the Docker network (the proxy image has busybox wget)
probe() { dc exec -T proxy wget -q -O /dev/null -T 5 "$1" >/dev/null 2>&1; }
answers() { probe "$(probe_url "$1")"; }

# While waiting: a spinner line on a terminal; otherwise one plain line every 30 s
progress() {   # progress <service> <elapsed> <state>
  if spin_on; then spin_sleep 3 "waiting for $(app_name "$1")  $2s  ($3)"
  else
    [ $(($2 % 30)) -lt 3 ] && printf '      waiting for %s: %ss (%s)\n' "$1" "$2" "$3"
    sleep 3
  fi
}

show_logs() { warn "last log lines of $1:"; dc logs --no-color --tail 40 "$1" 2>&1 | sed 's/^/    /' >&2 || true; }

# Wait until a service with a healthcheck (postgres, keycloak) is healthy
wait_healthy() {   # wait_healthy <service> [timeout]
  local svc=$1 t=${2:-$WAIT_TIMEOUT} start=$SECONDS st
  while :; do
    st=$(health_status "$svc")
    case $st in
      healthy) status_clear; ok "$(app_name "$svc") is ready ($((SECONDS - start))s)"; return 0 ;;
      unhealthy|exited|dead) status_clear; show_logs "$svc"; die "$svc did not start ($st) - see the log lines above" ;;
    esac
    if [ $((SECONDS - start)) -gt "$t" ]; then
      status_clear; show_logs "$svc"; die "$svc was not ready after ${t}s (slow computer? set WAIT_TIMEOUT=1800 in install.conf and re-run)"
    fi
    progress "$svc" $((SECONDS - start)) "$(container_state "$svc")"
  done
}

# Wait until a component answers its probe URL. Returns 1 (does not exit) on timeout.
wait_answer() {   # wait_answer <service> [timeout]
  local svc=$1 t=${2:-$WAIT_TIMEOUT} start=$SECONDS
  while ! answers "$svc"; do
    if [ $((SECONDS - start)) -gt "$t" ]; then
      status_clear; show_logs "$svc"; warn "$svc did not answer within ${t}s"; return 1
    fi
    progress "$svc" $((SECONDS - start)) "$(container_state "$svc")"
  done
  status_clear; ok "$(app_name "$svc") is up ($((SECONDS - start))s)"
}

# docker compose up -d (with a spinner), with a readable hint when a port is taken
compose_up() {   # compose_up [up options] <services...>
  local out what
  local s; what=""
  for s in "$@"; do case $s in -*) ;; *) what="$what $s" ;; esac; done
  what=$(app_names "$what")
  [ "$what" != none ] || what=everything
  if ! out=$(spin "starting $what" dc up -d "$@"); then
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    case $out in
      *"port is already allocated"*|*"address already in use"*|*"bind:"*)
        die "Port $HTTPS_PORT or $HTTP_PORT is already used by another program on this computer. Stop that program, or set HTTPS_PORT / HTTP_PORT in install.conf (e.g. 8443 / 8080) and re-run." ;;
      *"didn't complete successfully"*|*"exited with code"*)
        die "A start-up step failed - see the lines above (./ol-hub-docker.sh logs <service> shows more)" ;;
    esac
    die "docker compose up $* failed - see the lines above"
  fi
}

# ---- SQL ------------------------------------------------------------------------------------------------
# In the bundled PostgreSQL container (local socket), or with an external DB in a throw-away container.
# SQL is passed on stdin; extra psql arguments (e.g. -v name=value) are passed through.
psql_stdin() {
  if [ "$BUNDLED_DB" = true ]; then
    dc exec -T postgres psql -v ON_ERROR_STOP=1 -U "$OL_DB_USER" -d "$OL_DB_NAME" -At "$@" | tr -d '\r'
  else
    PGPASSWORD="$OL_DB_PASSWORD" docker run --rm -i --network "$NETWORK" -e PGPASSWORD "$IMAGE_POSTGRES" \
      psql -v ON_ERROR_STOP=1 -h "$OL_DB_HOST" -p "$OL_DB_PORT" -U "$OL_DB_USER" -d "$OL_DB_NAME" -At "$@" | tr -d '\r'
  fi
}
psql_c() { printf '%s\n' "$1" | psql_stdin; }

db_prepare() {
  # Keycloak keeps its tables in its own schema and starts before the Hub: make sure the schema exists
  # (the bundled database creates it on its first start; this covers older volumes and external databases)
  psql_c "SET client_min_messages TO warning; CREATE SCHEMA IF NOT EXISTS keycloak;" >/dev/null || die "cannot reach the database $OL_DB_HOST:$OL_DB_PORT/$OL_DB_NAME"
  ok "database ready (schema keycloak)"
}
