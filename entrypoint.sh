#!/bin/sh

# Variables

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
SMTP_USERNAME=${SMTP_USERNAME:=user}
SMTP_PASSWORD=${SMTP_PASSWORD:=Password123}

# Postfix

postconf -e myhostname=${MAIL_HOST}
postconf -e myorigin=${MAIL_DOMAIN}
postconf -e maillog_file=/dev/stdout

# SASL

postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination

# SMTP TLS

CRT_FILE=/tls/server.crt
KEY_FILE=/tls/server.key

if [[ -f "${CRT_FILE}" && -f "${KEY_FILE}" ]]; then
  postconf -e smtp_tls_security_level=may
  postconf -e smtpd_tls_security_level=may
  postconf -e smtpd_tls_cert_file=${CRT_FILE}
  postconf -e smtpd_tls_key_file=${KEY_FILE}

  postconf -Me smtps/inet="smtps inet n - - - - smtpd -o smtpd_tls_wrappermode=yes"
fi

# Dovecot

postconf -e smtpd_sasl_type=dovecot
postconf -e smtpd_sasl_path=private/auth

CRYPT_PASSWD=`doveadm pw -p "${SMTP_PASSWORD}"`

cat > /etc/dovecot/passwd <<EOF
${SMTP_USERNAME}@${MAIL_DOMAIN}:${CRYPT_PASSWD}:1000:1000::::
EOF

# IMAP TLS

if [[ -f "${CRT_FILE}" && -f "${KEY_FILE}" ]]; then
  cat >> /etc/dovecot/dovecot.conf <<EOF
ssl      = required
ssl_cert = <${CRT_FILE}
ssl_key  = <${KEY_FILE}
EOF
fi

# Custom configuration

if [[ -f /configure.sh ]]; then
  bash /configure.sh
fi

exec "$@"
