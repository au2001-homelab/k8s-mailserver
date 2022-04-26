#!/bin/sh

# Variables

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}

# Postfix

postconf -e myhostname=${MAIL_HOST}
postconf -e mydomain=${MAIL_DOMAIN}
postconf -e myorigin=${MAIL_DOMAIN}
postconf -e maillog_file=/var/log/mail.log

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
