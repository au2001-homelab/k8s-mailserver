#!/bin/bash

# A listening SMTP port proves very little. Postfix goes on accepting mail
# while Dovecot is dead, and the mail then sits in the queue because delivery
# over LMTP and SMTP authentication both depend on sockets Dovecot owns. So
# check every supervised process, and check those two sockets exist.

set -uo pipefail

readonly SUPERVISORD_CONF=/etc/supervisor/conf.d/supervisord.conf

# A non-zero exit only means some process is not running, which is reported
# below; an unreachable supervisord is what has to be told apart here.
status=$(supervisorctl -c "${SUPERVISORD_CONF}" status 2>&1) || true

if [[ -z "${status}" ]] || grep -qiE "refused connection|no such file" <<< "${status}"; then
  echo "supervisord is not answering: ${status}"
  exit 1
fi

if awk '$2 != "RUNNING" { print $1 " is " $2; stopped = 1 } END { exit !stopped }' <<< "${status}"; then
  exit 1
fi

for socket in /var/spool/postfix/private/auth /var/spool/postfix/private/dovecot-lmtp; do
  if [[ ! -S "${socket}" ]]; then
    echo "${socket} is missing: Dovecot is not serving authentication or delivery"
    exit 1
  fi
done
