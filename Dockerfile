ARG ARCH=amd64

FROM prom/node-exporter:v1.5.0 AS node-exporter

FROM alpine:3.16

COPY --from=node-exporter /bin/node_exporter /bin/

ENV KUBECTL_VERSION="v1.8.8"

RUN apk add --update curl bash coreutils \
    && export ARCH=$([[ "$(uname -m)" == "aarch64" ]] && echo "arm64" || echo "amd64") \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# add user
RUN addgroup --gid 1000 dind-volume-utils && \
    adduser --uid 1000 --gecos "" --disabled-password \
    --ingroup dind-volume-utils \
    --home /home/dind-volume-utils \
    --shell /bin/bash dind-volume-utils

WORKDIR /home/dind-volume-utils

ADD bin ./bin
ADD monitor ./monitor
ADD dind-metrics ./dind-metrics
ADD local-volumes ./local-volumes

RUN chown -R dind-volume-utils:dind-volume-utils /home/dind-volume-utils && \
    chmod 755 /home/dind-volume-utils

USER dind-volume-utils:dind-volume-utils

CMD ["/bin/bash"]
