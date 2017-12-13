FROM alpine:3.6


ENV KUBECTL_VERSION="v1.7.11"

RUN apk add --update curl bash \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

ADD bin /usr/local/bin


CMD ["/bin/bash"]