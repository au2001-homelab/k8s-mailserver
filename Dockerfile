# Pinned by digest so a rebuild cannot move release underneath the
# configuration. dovecot.conf is written against the Dovecot 2.4 series, which
# this release ships; 2.3 and 2.4 reject each other's configuration outright,
# so moving to a release carrying a different series means migrating that file
# in the same commit.
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
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
COPY ./entrypoint.sh ./healthcheck.sh ./tls-reload.sh /

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
