# Alpine 3.21 is the last release shipping Dovecot 2.3. Dovecot 2.4 rejects the
# configuration in this repository at startup, so this pin must not be raised
# before dovecot.conf is migrated. Alpine 3.21 is supported until 2026-11-01.
FROM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d
LABEL maintainer="Aurélien GARNIER <me@arl.sh>"

RUN apk add --no-cache \
      bash \
      ca-certificates \
      dovecot \
      dovecot-lmtpd \
      dovecot-pigeonhole-plugin \
      dovecot-pop3d \
      opendkim \
      opendmarc \
      postfix \
      supervisor \
      syslog-ng

# OpenDMARC derives organizational domains from a public suffix list. Without
# one it only ever queries the From domain itself, so a policy published at
# example.com is never found for mail claiming to be from sub.example.com and
# the spoof is reported as dmarc=none. No Alpine package ships the list.
RUN mkdir -p /etc/opendmarc \
 && wget -qO /etc/opendmarc/public_suffix_list.dat \
      https://publicsuffix.org/list/public_suffix_list.dat \
 && grep -q '^// ===BEGIN ICANN DOMAINS===' /etc/opendmarc/public_suffix_list.dat

# Alpine carried a legacy postmaster account in its base layout up to 3.19 and
# dropped it afterwards. Dovecot owns the mail store as that user, so without it
# Dovecot refuses to start. It has to keep uid 14: every message already on the
# persistent volume is owned by that id, and any other value would lock the
# server out of the existing mail.
RUN adduser -S -D -H -h /var/mail -s /sbin/nologin -G mail -u 14 postmaster \
 && [ "$(id -u postmaster)" = "14" ] \
 && mkdir -p /tls

COPY ./supervisord.conf /etc/supervisor/conf.d/
COPY ./dovecot.conf /etc/dovecot/
COPY ./opendkim.conf /etc/opendkim/
COPY ./syslog-ng.conf /etc/syslog-ng/
COPY ./entrypoint.sh ./healthcheck.sh /

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
