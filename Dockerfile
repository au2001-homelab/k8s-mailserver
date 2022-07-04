FROM alpine:latest
LABEL maintainer="Aurélien GARNIER <me@arl.sh>"

RUN apk add --update --upgrade --no-cache supervisor syslog-ng
RUN apk add --update --upgrade --no-cache postfix
RUN apk add --update --upgrade --no-cache dovecot dovecot-pop3d dovecot-lmtpd
RUN apk add --update --upgrade --no-cache postfix-policyd-spf-perl
RUN apk add --update --upgrade --no-cache opendkim
RUN apk add --update --upgrade --no-cache opendmarc
RUN rm -rf /etc/apk/cache

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
