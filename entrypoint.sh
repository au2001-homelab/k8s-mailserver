#!/bin/bash

set -euo pipefail

# Variables

# Refuse to start rather than fall back to defaults: this server is reachable
# from the internet, so a mistyped or empty variable used to silently publish a
# mailbox with a well-known password. The :? form also rejects empty values.
: "${MAIL_DOMAINS:?is required, e.g. \"example.com example.net\"}"
: "${USERNAME:?is required}"
: "${PASSWORD:?is required}"

MAIL_DOMAINS=(${MAIL_DOMAINS})
MAIL_HOST=${MAIL_HOST:-${MAIL_DOMAINS[0]}}

TLS_CRT_FILE=/tls/server.crt
TLS_KEY_FILE=/tls/server.key

for file in "${TLS_CRT_FILE}" "${TLS_KEY_FILE}"; do
  if [[ ! -f "${file}" ]]; then
    echo "${file} is missing: refusing to serve mail without TLS." >&2
    exit 1
  fi
done

for domain in "${MAIL_DOMAINS[@]}"; do
  if [[ ! -f "/etc/opendkim/keys/${domain}/default.private" ]]; then
    echo "DKIM key for ${domain} is missing: outbound mail would be rejected." >&2
    exit 1
  fi
done

# Postfix

postconf -e myhostname="${MAIL_HOST}"
postconf -e mydomain="${MAIL_DOMAINS[0]}"
postconf -e myorigin="\$mydomain"
postconf -e mydestination=""
postconf -e virtual_mailbox_domains="${MAIL_DOMAINS[*]}"
# The client address comes from an unauthenticated PROXY protocol header, so
# any peer able to reach the SMTP port can claim any address. Trusting the
# cluster range here handed relay rights to every pod in the cluster.
postconf -e mynetworks="127.0.0.0/8, [::1]/128"

# Relay rights are granted by authentication alone. Left unset, Postfix applies
# its default of permit_mynetworks first, which reintroduces the trust above.
postconf -e smtpd_relay_restrictions="permit_sasl_authenticated, reject_unauth_destination"

postconf -e smtpd_recipient_restrictions="permit_sasl_authenticated, reject_non_fqdn_recipient, reject_unknown_reverse_client_hostname, reject_unauth_destination, permit"
postconf -e smtpd_sender_restrictions="permit_sasl_authenticated, reject_non_fqdn_sender, reject_unknown_reverse_client_hostname, permit"
postconf -e smtpd_helo_required="yes"
postconf -e smtpd_helo_restrictions="permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname, permit"

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

# Authentication is offered by the submission service alone. The MX must not
# advertise it: that is what exposed the mailbox password to the credential
# stuffing every public port 25 receives.
postconf -e smtpd_sasl_auth_enable="no"
postconf -e broken_sasl_auth_clients="yes"
postconf -e smtpd_sasl_type="dovecot"
postconf -e smtpd_sasl_path="private/auth"

# Dovecot delivers as postmaster, but a freshly provisioned volume arrives
# owned by root with no group write, so without this every delivery fails to
# create the mailbox and mail sits in the queue until it bounces.
install -d -o postmaster -g root -m 0750 /var/spool/mail/vhosts

CRYPT_PASSWORD=`doveadm pw -p "${PASSWORD}"`

cat > /etc/dovecot/passwd <<EOF
${USERNAME}@${MAIL_DOMAINS[0]}:${CRYPT_PASSWORD}
EOF

# SMTP TLS

postconf -e smtpd_tls_cert_file="${TLS_CRT_FILE}"
postconf -e smtpd_tls_key_file="${TLS_KEY_FILE}"

# Opportunistic in both directions: a public MX has to keep accepting cleartext
# from senders that cannot negotiate TLS, and has to keep delivering to them.
postconf -e smtpd_tls_security_level="may"
postconf -e smtp_tls_security_level="may"

# Credentials, however, never travel in the clear.
postconf -e smtpd_tls_auth_only="yes"

postconf -e smtpd_tls_protocols=">=TLSv1.2"
postconf -e smtpd_tls_mandatory_protocols=">=TLSv1.2"
postconf -e smtp_tls_protocols=">=TLSv1.2"
postconf -e smtp_tls_mandatory_protocols=">=TLSv1.2"

# IMAP TLS

# Written to its own file rather than appended to dovecot.conf, so that running
# the entrypoint twice against the same filesystem cannot stack up duplicates.
cat > /etc/dovecot/local.conf <<EOF
ssl              = required
ssl_cert         = <${TLS_CRT_FILE}
ssl_key          = <${TLS_KEY_FILE}
ssl_min_protocol = TLSv1.2
EOF

# DKIM

postconf -e smtpd_milters="unix:private/opendkim"
postconf -e non_smtpd_milters="\$smtpd_milters"
postconf -e milter_default_action="accept"

cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
::1
localhost
EOF

> /etc/opendkim/KeyTable
> /etc/opendkim/SigningTable

for domain in "${MAIL_DOMAINS[@]}"; do
  cat >> /etc/opendkim/KeyTable <<EOF
default._domainkey.${domain} ${domain}:default:/etc/opendkim/keys/${domain}/default.private
EOF

  cat >> /etc/opendkim/SigningTable <<EOF
*@${domain} default._domainkey.${domain}
EOF

  cat >> /etc/opendkim/TrustedHosts <<EOF
${domain}
EOF
done

# DMARC

postconf -e smtpd_milters="$(postconf -ph smtpd_milters),unix:private/opendmarc"

cat > /etc/opendmarc.conf <<EOF
AuthservID                 ${MAIL_HOST}
TrustedAuthservIDs         ${MAIL_HOST}
IgnoreAuthenticatedClients true
PublicSuffixList           /etc/opendmarc/public_suffix_list.dat
RequiredHeaders            true
SPFIgnoreResults           true
SPFSelfValidate            true
Socket                     unix:/var/spool/postfix/private/opendmarc
Syslog                     true
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
postconf -Me 10025/inet="10025 inet n - - - 1 postscreen"
postconf -Me smtpd/pass="smtpd pass - - - - - smtpd"

postconf -e postscreen_upstream_proxy_protocol="haproxy"
postconf -e postscreen_access_list="permit_mynetworks"

# Submission gets its own service rather than sharing the MX port. Mail clients
# have no business passing through postscreen, which exists to screen MX
# traffic, and submission demands what the MX cannot: mandatory TLS,
# authentication for every message, and no HELO policy, since mail clients
# routinely greet with an unqualified laptop name.
postconf -Me 10587/inet="10587 inet n - - - - smtpd -o syslog_name=postfix/submission -o smtpd_upstream_proxy_protocol=haproxy -o smtpd_tls_security_level=encrypt -o smtpd_sasl_auth_enable=yes -o smtpd_client_restrictions=permit_sasl_authenticated,reject -o smtpd_relay_restrictions=permit_sasl_authenticated,reject -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject -o smtpd_sender_restrictions=permit_sasl_authenticated,reject -o smtpd_helo_restrictions="

# Custom configuration

if [[ -f /configure.sh ]]; then
  bash /configure.sh
fi

exec "$@"
