# Alpine 3.21 is the last release shipping Dovecot 2.3. Dovecot 2.4 rejects the
# configuration in this repository at startup, so this pin must not be raised
# before dovecot.conf is migrated. Alpine 3.21 is supported until 2026-11-01.
FROM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d
LABEL maintainer="Aurélien GARNIER <me@arl.sh>"

RUN apk add --update --upgrade --no-cache bash
RUN apk add --update --upgrade --no-cache supervisor syslog-ng
RUN apk add --update --upgrade --no-cache postfix
RUN apk add --update --upgrade --no-cache dovecot dovecot-pop3d dovecot-lmtpd
RUN apk add --update --upgrade --no-cache opendkim opendmarc
RUN apk add --update --upgrade --no-cache dovecot-pigeonhole-plugin
RUN rm -rf /etc/apk/cache

# OpenDMARC derives organizational domains from a public suffix list. Without
# one it only ever queries the From domain itself, so a policy published at
# example.com is never found for mail claiming to be from sub.example.com and
# the spoof is reported as dmarc=none. No Alpine package ships the list.
RUN apk add --update --upgrade --no-cache ca-certificates \
 && mkdir -p /etc/opendmarc \
 && wget -qO /etc/opendmarc/public_suffix_list.dat \
      https://publicsuffix.org/list/public_suffix_list.dat \
 && grep -q '^// ===BEGIN ICANN DOMAINS===' /etc/opendmarc/public_suffix_list.dat

RUN mkdir -p /etc/sasl2
RUN mkdir -p /tls

COPY ./supervisord.conf /etc/supervisor/conf.d/
COPY ./sasl.conf /etc/postfix/sasl/smtpd.conf
COPY ./dovecot.conf /etc/dovecot/
COPY ./opendkim.conf /etc/opendkim/
COPY ./syslog-ng.conf /etc/syslog-ng/

COPY ./entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
