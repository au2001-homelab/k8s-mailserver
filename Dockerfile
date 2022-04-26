FROM alpine:latest
LABEL maintainer="Aurélien Garnier <me@arl.sh>"

RUN apk update
RUN apk add --upgrade supervisor postfix
RUN rm -rf /etc/apk/cache

COPY ./entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord"]
