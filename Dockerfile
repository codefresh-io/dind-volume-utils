FROM alpine:3.20.1

COPY --from=prom/node-exporter:v1.8.1 /bin/node_exporter /usr/local/bin/
COPY --from=bitnami/kubectl:1.30.2 /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/

RUN apk add --update bash coreutils

WORKDIR /home/dind-volume-utils

COPY bin ./bin
COPY monitor ./monitor
COPY dind-metrics ./dind-metrics
COPY local-volumes ./local-volumes

CMD ["sh"]
