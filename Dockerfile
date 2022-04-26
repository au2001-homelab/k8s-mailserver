FROM alpine:latest
LABEL maintainer="Aurélien GARNIER <me@arl.sh>"

RUN apk update
RUN apk add --upgrade supervisor postfix
RUN rm -rf /etc/apk/cache

COPY ./supervisord.conf /etc/supervisor/conf.d/

COPY ./postfix.sh /
RUN chmod +x /postfix.sh

COPY ./entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
