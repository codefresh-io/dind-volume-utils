ARG ARCH=amd64

FROM prom/node-exporter:v1.0.0 AS node-exporter

FROM alpine:3.16

COPY --from=node-exporter /bin/node_exporter /bin/

ENV KUBECTL_VERSION="v1.8.8"

RUN apk add --update curl bash coreutils \
    && export ARCH=$([[ "$(uname -m)" == "aarch64" ]] && echo "arm64" || echo "amd64") \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

ADD bin /bin
ADD monitor /monitor
ADD dind-metrics /dind-metrics
ADD local-volumes /local-volumes


CMD ["/bin/bash"]
