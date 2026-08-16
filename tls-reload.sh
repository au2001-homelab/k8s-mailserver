#!/bin/bash

# cert-manager renews the certificate into the mounted secret and the new file
# appears in place, but Dovecot reads the certificate once while parsing its
# configuration and never looks at the file again. A pod that outlives a
# renewal therefore goes on presenting the old certificate until something
# restarts it, and eventually presents an expired one.
#
# Reloading in place rather than replacing the pod is deliberate: the Postfix
# queue lives on the container filesystem, so replacing the container would
# discard whatever has been accepted but not yet delivered.
#
# Postfix needs no equivalent. Its smtpd processes are short lived and read the
# certificate as each one starts, so a renewal reaches SMTP on its own.

set -uo pipefail

readonly CERTIFICATE=/tls/server.crt
readonly INTERVAL=${TLS_RELOAD_INTERVAL:-300}

fingerprint() {
  sha256sum "${CERTIFICATE}" 2>/dev/null | cut -d' ' -f1
}

current=$(fingerprint)

while sleep "${INTERVAL}"; do
  latest=$(fingerprint)

  # An empty reading means the file is momentarily absent, which is what a
  # projected secret update looks like from here. Wait for the next round
  # rather than reacting to it.
  if [[ -z "${latest}" || "${latest}" == "${current}" ]]; then
    continue
  fi

  echo "TLS certificate changed, reloading Dovecot"
  if doveadm reload; then
    current=${latest}
  else
    echo "Dovecot reload failed; will retry in ${INTERVAL}s" >&2
  fi
done
