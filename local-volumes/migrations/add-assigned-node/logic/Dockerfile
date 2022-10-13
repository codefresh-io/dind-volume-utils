ARG ARCH=amd64

FROM alpine:3.15

ENV KUBECTL_VERSION="v1.24.0"

RUN apk add --update curl bash coreutils \
    && export ARCH=$([[ "$(uname -m)" == "aarch64" ]] && echo "arm64" || echo "amd64") \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

ADD add_assigned_node.sh /add_assigned_node.sh

CMD ["/bin/bash", "add_assigned_node.sh"]
