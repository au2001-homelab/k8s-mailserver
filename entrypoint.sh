#!/bin/sh

# Variables

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
USERNAME=${USERNAME:=user}
PASSWORD=${PASSWORD:=Password123}

# Postfix

postconf -e myhostname="${MAIL_HOST}"
postconf -e myorigin="${MAIL_DOMAIN}"
postconf -e mydestination=""
postconf -e virtual_mailbox_domains="${MAIL_DOMAIN}"

# postconf -e smtpd_recipient_restrictions="permit_mynetworks, permit_sasl_authenticated, reject_unknown_client_hostname, reject_unauth_destination, check_policy_service unix:private/policyd-spf"
postconf -e smtpd_recipient_restrictions="permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination, check_policy_service unix:private/policyd-spf, permit"
postconf -e smtpd_helo_required="yes"
postconf -e smtpd_helo_restrictions="permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname, permit"

postconf -e mailbox_size_limit="0"
postconf -e maillog_file="/dev/stdout"

postconf -e smtpd_banner="${MAIL_HOST} ESMTP"
postconf -e smtp_header_checks="regexp:/etc/postfix/header_checks"
cat > /etc/postfix/header_checks <<EOF
/^Received:/ IGNORE
/^From:/     PREPEND List-Unsubscribe: <mailto:unsubscribe@${MAIL_DOMAIN}>
EOF

postconf -e virtual_alias_maps="lmdb:/etc/postfix/aliases"
echo "@${MAIL_DOMAIN} ${USERNAME}@${MAIL_DOMAIN}" > /etc/postfix/aliases
postmap lmdb:/etc/postfix/aliases

# Dovecot

postconf -e virtual_transport="lmtp:unix:private/dovecot-lmtp"

postconf -e smtpd_sasl_auth_enable="yes"
postconf -e broken_sasl_auth_clients="yes"
postconf -e smtpd_sasl_type="dovecot"
postconf -e smtpd_sasl_path="private/auth"

CRYPT_PASSWORD=`doveadm pw -p "${PASSWORD}"`

cat > /etc/dovecot/passwd <<EOF
${USERNAME}@${MAIL_DOMAIN}:${CRYPT_PASSWORD}
EOF

# SMTP TLS

TLS_CRT_FILE=/tls/server.crt
TLS_KEY_FILE=/tls/server.key

if [[ -f "${TLS_CRT_FILE}" && -f "${TLS_KEY_FILE}" ]]; then
  postconf -e smtp_tls_security_level=may
  postconf -e smtpd_tls_security_level=may
  postconf -e smtpd_tls_cert_file=${TLS_CRT_FILE}
  postconf -e smtpd_tls_key_file=${TLS_KEY_FILE}

  postconf -Me smtps/inet="smtps inet n - - - - smtpd -o smtpd_tls_wrappermode=yes"
fi

# IMAP TLS

if [[ -f "${TLS_CRT_FILE}" && -f "${TLS_KEY_FILE}" ]]; then
  cat >> /etc/dovecot/dovecot.conf <<EOF
ssl      = required
ssl_cert = <${TLS_CRT_FILE}
ssl_key  = <${TLS_KEY_FILE}
EOF
else
  cat >> /etc/dovecot/dovecot.conf <<EOF
ssl = no
EOF
fi

# DKIM

postconf -e smtpd_milters="unix:private/opendkim,unix:private/opendmarc"
postconf -e non_smtpd_milters="unix:private/opendkim,unix:private/opendmarc"
postconf -e milter_default_action="accept"

cat > /etc/opendkim/KeyTable <<EOF
default._domainkey.${MAIL_DOMAIN} ${MAIL_DOMAIN}:default:/etc/opendkim/keys/${MAIL_DOMAIN}/default.private
EOF

cat > /etc/opendkim/SigningTable <<EOF
*@${MAIL_DOMAIN} default._domainkey.${MAIL_DOMAIN}
EOF

cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
${MAIL_DOMAIN}
EOF

# SPF

postconf -Me policyd-spf/unix="policyd-spf unix - n n - - spawn argv=/usr/sbin/postfix-policyd-spf-perl"
postconf -e policyd-spf_time_limit="3600"

# DMARC

cat > /etc/opendmarc.conf <<EOF
AuthservID                 OpenDMARC
TrustedAuthservIDs         ${MAIL_HOST}
RejectFailures             true
IgnoreAuthenticatedClients true
RequiredHeaders            true
SPFSelfValidate            true
Socket                     unix:/var/spool/postfix/private/opendmarc
UMask                      0660
UserID                     root:postfix
EOF

# Custom configuration

if [[ -f /configure.sh ]]; then
  bash /configure.sh
fi

exec "$@"
