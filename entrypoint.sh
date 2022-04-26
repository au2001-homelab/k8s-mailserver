#!/bin/bash

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
SMTP_USER=${SMTP_USER:=user:password}
DKIM_SELECTOR=${DKIM_SELECTOR:=mail}
CRON_ENABLED=${LOGS_CLEANUP:=1}

# Supervisor

cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon = true
user     = root

[program:postfix]
command                 = /postfix.sh
stdout_logfile          = /dev/stdout
stderr_logfile          = /dev/stderr
stdout_logfile_maxbytes = 0
stderr_logfile_maxbytes = 0

[program:maillog2stdout]
command                 = tail -f /var/log/mail.log
stdout_logfile          = /dev/stdout
stderr_logfile          = /dev/stderr
stdout_logfile_maxbytes = 0
stderr_logfile_maxbytes = 0
EOF

# Postfix

cat > /postfix.sh <<EOF
#!/bin/bash
trap "postfix stop" SIGINT
trap "postfix stop" SIGTERM
trap "postfix reload" SIGHUP
postfix start
sleep 5
while kill -0 "$(cat /var/spool/postfix/pid/master.pid)"; do
  sleep 5
done
EOF

chmod +x /postfix.sh

postconf -e myhostname=${MAIL_HOST}
postconf -e mydomain=${MAIL_DOMAIN}
postconf -e myorigin=${MAIL_DOMAIN}

# TLS

CRT_FILE=/etc/postfix/certs/${MAIL_HOST}.crt
KEY_FILE=/etc/postfix/certs/${MAIL_HOST}.key

if [[ -f "${CRT_FILE}" && -f "${KEY_FILE}" ]]; then
  postconf -e smtpd_use_tls=yes
  postconf -e smtpd_tls_cert_file=${CRT_FILE}
  postconf -e smtpd_tls_key_file=${KEY_FILE}
  postconf -e smtpd_tls_security_level=may
  postconf -e smtp_tls_security_level=may
fi

# Custom configuration

if [[ -f "/configure.sh" ]]; then
  bash /configure.sh
fi

exec "$@"
