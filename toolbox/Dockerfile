# scripts need bash; distroless has no shell
FROM debian:trixie-slim AS download

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.36.6
ARG HELM_VERSION=v4.3.1
ARG K3D_VERSION=v5.9.0
ARG TERRAFORM_VERSION=1.17.1
ARG K6_VERSION=v2.3.0

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip
WORKDIR /dl
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
# checksums come from the same release servers so won't catch attacks
RUN get() { curl -fsSLO "$1"; } \
 && get "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  kubectl" | sha256sum -c - \
 && get "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && echo "$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz.sha256sum" | cut -d' ' -f1)  helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | sha256sum -c - \
 && tar -xzf "helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" --strip-components=1 "linux-${TARGETARCH}/helm" \
 && get "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${TARGETARCH}" \
 && echo "$(curl -fsSL "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/checksums.txt" | grep " _dist/k3d-linux-${TARGETARCH}$" | cut -d' ' -f1)  k3d-linux-${TARGETARCH}" | sha256sum -c - \
 && mv "k3d-linux-${TARGETARCH}" k3d \
 && get "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
 && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "_linux_${TARGETARCH}.zip$" | sha256sum -c - \
 && unzip -q "terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" terraform \
 && get "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-checksums.txt" | grep "linux-${TARGETARCH}.tar.gz$" | sha256sum -c - \
 && tar -xzf "k6-${K6_VERSION}-linux-${TARGETARCH}.tar.gz" --strip-components=1 "k6-${K6_VERSION}-linux-${TARGETARCH}/k6" \
 && mkdir /out && mv kubectl helm k3d terraform k6 /out/ && chmod 0755 /out/*

FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* /var/cache/debconf/*-old /usr/share/doc /usr/share/man
COPY --from=download /out/ /usr/local/bin/

# scripts check this to decide whether to re-exec themselves inside the toolbox
ENV IN_TOOLBOX=1
WORKDIR /work
