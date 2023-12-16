#!/bin/bash

# Variables

MAIL_DOMAINS=(${MAIL_DOMAINS:=example.com})
MAIL_HOST=${MAIL_HOST:-${MAIL_DOMAINS[0]}}
USERNAME=${USERNAME:=user}
PASSWORD=${PASSWORD:=Password123}

# Postfix

postconf -e myhostname="${MAIL_HOST}"
postconf -e mydomain="${MAIL_DOMAINS[0]}"
postconf -e myorigin="\$mydomain"
postconf -e mydestination=""
postconf -e virtual_mailbox_domains="${MAIL_DOMAINS[*]}"
postconf -e mynetworks="127.0.0.0/8, [::1]/128, 10.0.0.0/8"

postconf -e smtpd_recipient_restrictions="permit_sasl_authenticated, reject_non_fqdn_recipient, reject_unknown_client_hostname, reject_unauth_destination, permit"
postconf -e smtpd_sender_restrictions="permit_sasl_authenticated, reject_non_fqdn_sender, reject_unknown_client_hostname, permit"
postconf -e smtpd_helo_required="yes"
postconf -e smtpd_helo_restrictions="permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname, reject_unknown_helo_hostname, reject_unknown_client_hostname, permit"

postconf -e smtputf8_enable="no"

postconf -e mailbox_size_limit="0"
postconf -e maillog_file="/dev/stdout"

postconf -e smtpd_banner="${MAIL_HOST} ESMTP"
postconf -e smtp_header_checks="regexp:/etc/postfix/header_checks"
cat > /etc/postfix/header_checks <<EOF
/^Received:/ IGNORE
/^From:/     PREPEND List-Unsubscribe: <mailto:unsubscribe@${MAIL_DOMAINS[0]}>
EOF

postconf -e virtual_alias_maps="lmdb:/etc/postfix/aliases"
> /etc/postfix/aliases
for domain in "${MAIL_DOMAINS[@]}"; do
  cat >> /etc/postfix/aliases <<EOF
@${domain} ${USERNAME}@${MAIL_DOMAINS[0]}
EOF
done
postmap lmdb:/etc/postfix/aliases

# Dovecot

postconf -e virtual_transport="lmtp:unix:private/dovecot-lmtp"

postconf -e smtpd_sasl_auth_enable="yes"
postconf -e broken_sasl_auth_clients="yes"
postconf -e smtpd_sasl_type="dovecot"
postconf -e smtpd_sasl_path="private/auth"

CRYPT_PASSWORD=`doveadm pw -p "${PASSWORD}"`

cat > /etc/dovecot/passwd <<EOF
${USERNAME}@${MAIL_DOMAINS[0]}:${CRYPT_PASSWORD}
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

postconf -e smtpd_milters="unix:private/opendkim"
postconf -e non_smtpd_milters="\$smtpd_milters"
postconf -e milter_default_action="accept"

cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
EOF

for domain in "${MAIL_DOMAINS[@]}"; do
  cat >> /etc/opendkim/KeyTable <<EOF
default._domainkey.${domain} ${domain}:default:/etc/opendkim/keys/${domain}/default.private
EOF

  cat >> /etc/opendkim/SigningTable <<EOF
*@${domain} default._domainkey.${domain}
EOF

  cat > /etc/opendkim/TrustedHosts <<EOF
${domain}
EOF
done

# DMARC

postconf -e smtpd_milters="$(postconf -ph smtpd_milters),unix:private/opendmarc"

cat > /etc/opendmarc.conf <<EOF
AuthservID                 ${MAIL_HOST}
TrustedAuthservIDs         ${MAIL_HOST}
IgnoreAuthenticatedClients true
RequiredHeaders            true
SPFIgnoreResults           true
SPFSelfValidate            true
Socket                     unix:/var/spool/postfix/private/opendmarc
UMask                      0660
UserID                     root:postfix
EOF

mkdir -p /var/lib/dovecot/sieve/before.d/
mkdir -p /var/lib/dovecot/sieve/after.d/

cat > /var/lib/dovecot/sieve/after.d/opendmarc.sieve <<EOF
require ["fileinto"];

if header :matches "Authentication-Results" "*; dmarc=fail *" {
  fileinto "Spam";
  stop;
}
EOF

sievec /var/lib/dovecot/sieve/before.d/
sievec /var/lib/dovecot/sieve/after.d/

# Proxy Protocol

postconf -M# smtp/inet
postconf -M# smtps/inet
postconf -Me 10025/inet="10025 inet n - - - 1 postscreen"
postconf -Me smtpd/pass="smtpd pass - - - - - smtpd"

postconf -e postscreen_upstream_proxy_protocol="haproxy"
postconf -e postscreen_access_list="permit_mynetworks"

# Custom configuration

if [[ -f /configure.sh ]]; then
  bash /configure.sh
fi

exec "$@"
