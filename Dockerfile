FROM alpine:latest
LABEL maintainer="Aurélien GARNIER <me@arl.sh>"

RUN apk add --update --upgrade --no-cache supervisor postfix dovecot dovecot-pop3d dovecot-lmtpd opendkim
RUN rm -rf /etc/apk/cache

RUN mkdir -p /etc/sasl2
RUN mkdir -p /tls

RUN adduser -G root -h /var/spool/mail/vhosts -s /sbin/nologin -D emailuser

COPY ./supervisord.conf /etc/supervisor/conf.d/
COPY ./sasl.conf /etc/postfix/sasl/smtpd.conf
COPY ./dovecot.conf /etc/dovecot/
COPY ./opendkim.conf /etc/opendkim/

COPY ./entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
