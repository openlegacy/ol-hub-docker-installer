-- Runs once, when the bundled PostgreSQL creates its database (first start on an empty volume).
-- Keycloak keeps its tables in its own schema (KC_DB_SCHEMA=keycloak) and starts before the Hub, so the
-- schema must exist first. ol-hub-docker.sh runs the same statement on every install (also for an external DB).
CREATE SCHEMA IF NOT EXISTS keycloak;
