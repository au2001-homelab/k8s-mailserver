# k8s-mailserver

A simple mail server container for single-user, but multi-domain setups.\
Postfix for SMTP, Dovecot for IMAP, OpenDKIM and OpenDMARC for authentication.

It is built to run on Kubernetes behind a load balancer that speaks the PROXY protocol, so it can see the real client IP address instead of the balancer's

## What it does

- Catches all mail for every configured domain (anything addressed to `@example.com`).
- Delivers it all into one mailbox.
- Offers submission and IMAP to mail clients, both requiring TLS.
- Signs outgoing mail with DKIM.
- Filters spam by checking SPF, DKIM and DMARC.
- No content filtering: 100% of valid emails are accepted.

## Configuration

| Variable | Required | Meaning |
| --- | --- | --- |
| `MAIL_DOMAINS` | yes | Space-separated domains to accept mail for. The first is the primary: it owns the mailbox everything else is aliased to. |
| `USERNAME` | yes | Local part of the one mailbox. `USERNAME@<first domain>` is the login. |
| `PASSWORD` | yes | Its password. |
| `MAIL_HOST` | no | The name this server calls itself: HELO, banner, and the identifier it stamps on its own authentication results. Defaults to the first domain. |
| `DKIM_SELECTOR` | no | Which DKIM record signs outgoing mail. Defaults to `default`. |

### Mounts

| Path | Contents |
| --- | --- |
| `/tls/server.crt`, `/tls/server.key` | Certificate and key, used by SMTP and IMAP alike. |
| `/etc/opendkim/keys/<domain>/<selector>.private` | One private key per domain, named after `DKIM_SELECTOR`. |
| `/var/spool/mail/vhosts` | The mail store. This is the volume that matters. |

The mail store is owned by uid 14.

Note: the Postfix queue lives on the container ephemeral filesystem, not in a volume, so mail that has been accepted but not yet delivered is lost when the pod is replaced. Keep that in mind when choosing how aggressively to restart it.

### Extending it

If `/configure.sh` exists it is run just before the services start, after all generated configuration is in place. It runs as root and can change anything; it is the intended way to add settings this image does not expose.

## Ports

| Port | Protocol | Notes |
| --- | --- | --- |
| 10025 | SMTP (MX) | Behind postscreen. Offers no authentication at all. |
| 10587 | Submission | TLS required before authentication; every message must be authenticated. |
| 143 | IMAP | STARTTLS. |
| 993 | IMAPS | Implicit TLS. |

**Every one of these expects a PROXY protocol header.**\
Anyone with direct access to the pod can thus impersonate any client's IP address.\
Make sure to restrict who can reach it with a NetworkPolicy.

The unusual port numbers assume the balancer will map the public 25, 587, 143 and 993 onto them.

## What has to exist in DNS

You will need to set this all up correctly, or you outgoing mail will silently be sent to spam:

- **MX** for each domain, pointing at names that resolve to this server.
- **PTR** for each address it sends from, matching the name it greets with, and resolving forward again to the same address.
- **SPF** authorising those addresses.
- **DKIM**: `<selector>._domainkey.<domain>` carrying the public key for each private key mounted above. 2048-bit RSA is recommended.
- **DMARC**: `_dmarc.<domain>`.

## Releases

Every build of `main` publishes an immutable version naming what is inside it:

```
dovecot2.4.4-postfix3.11.6-alpine3.24.1-b20260816184325
```

The trailing component is a UTC timestamp, used for ordering.\
`latest` always follows the newest build, and each commit also gets a `sha-` tag.

Updates are checked automatically every week for fixes, and a new version is published if needed.

## Running it locally

```sh
docker build -t mailserver .

mkdir -p tls dkim/example.org
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=mail.example.org -keyout tls/server.key -out tls/server.crt
openssl genrsa -out dkim/example.org/default.private 2048

docker run --rm \
  -e MAIL_DOMAINS=example.org \
  -e MAIL_HOST=mail.example.org \
  -e USERNAME=user \
  -e PASSWORD=123 \
  -v "$PWD/tls:/tls:ro" \
  -v "$PWD/dkim:/etc/opendkim/keys:ro" \
  mailserver
```
