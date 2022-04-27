#!/bin/sh

# Variables

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
SMTP_USERNAME=${SMTP_USERNAME:=user}
SMTP_PASSWORD=${SMTP_PASSWORD:=Password123}

# Postfix

postconf -e myhostname=${MAIL_HOST}
postconf -e myorigin=${MAIL_DOMAIN}
postconf -e maillog_file=/var/log/mail.log

# SASL

postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination

echo "${SMTP_PASSWORD}" | saslpasswd2 -pcu "${MAIL_HOST}" "${SMTP_USERNAME}"
chown postfix /etc/sasl2/sasldb2

# TLS

CRT_FILE=/etc/postfix/certs/${MAIL_HOST}.crt
KEY_FILE=/etc/postfix/certs/${MAIL_HOST}.key

if [[ -f "${CRT_FILE}" && -f "${KEY_FILE}" ]]; then
  postconf -e smtpd_use_tls=yes
  postconf -e smtpd_enforce_tls=yes
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
