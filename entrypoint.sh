#!/bin/sh

# Variables

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
USERNAME=${USERNAME:=user}
PASSWORD=${PASSWORD:=Password123}

# Postfix

echo "@${MAIL_HOST} ${USERNAME}@${MAIL_HOST}" >> /etc/postfix/virtual
postmap /etc/postfix/virtual

echo "${MAIL_DOMAIN}" > /etc/mailname

postconf -e myhostname=${MAIL_HOST}
postconf -e myorigin=/etc/mailname
postconf -e mydestination=mail.${MAIL_DOMAIN},${MAIL_DOMAIN},localhost
postconf -e virtual_alias_maps=hash:/etc/postfix/virtual
postconf -e mynetworks=127.0.0.0/8
postconf -e relayhost=
postconf -e mailbox_size_limit=0
postconf -e maillog_file=/dev/stdout

# SASL

postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject

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

CRYPT_PASSWORD=`doveadm pw -p "${PASSWORD}"`

cat > /etc/dovecot/passwd <<EOF
${USERNAME}@${MAIL_DOMAIN}:${CRYPT_PASSWORD}:1000:1000::::
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
