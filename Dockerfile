FROM quay.io/prometheus/node-exporter:v0.15.1 AS node-exporter

FROM alpine:3.6

COPY --from=node-exporter /bin/node_exporter /bin/

ENV KUBECTL_VERSION="v1.8.8"

RUN apk add --update curl bash coreutils \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

ADD bin /bin
ADD monitor /monitor
ADD dind-metrics /dind-metrics
ADD local-volumes /local-volumes


CMD ["/bin/bash"]