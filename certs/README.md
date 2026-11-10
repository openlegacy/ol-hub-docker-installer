# certs

- **TLS_MODE=custom**: put your certificate here as `tls.crt` (the full chain: certificate first, then the
  intermediates) and its private key as `tls.key`. The certificate must be valid for every OpenLegacy address
  (`ol-hub.<domain>`, `keycloak.<domain>`, `ol-code.<domain>`, `ol-terminal.<domain>`,
  `ol-dataiq-batch.<domain>`); a wildcard certificate for `*.<domain>` is easiest. Then run `./ol-hub-docker.sh`.
- **TLS_MODE=selfsigned** (default): the installer saves the proxy's local certificate authority here as
  `openlegacy-root-ca.crt`. Trust it on the computers that open the Hub to get rid of the browser warning
  (`./ol-hub-docker.sh trust-certificate` on this computer; README > Certificates for the others).

Files in this folder are not committed to git.
