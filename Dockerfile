# 运行时需 cap: NET_ADMIN, NET_RAW, MKNOD 及 device cgroup (c 10:200)，与 vh-warp 一致
# Build stage
FROM golang:1.25-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /cfwarpxray .

# Runtime stage: Ubuntu 22.04 LTS (64-bit)
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 ca-certificates procps iproute2 dbus iptables \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Cloudflare WARP (Ubuntu 22.04 jammy)
RUN curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" | tee /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update && apt-get install -y cloudflare-warp \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/warp-xray /etc/cfwarpxray /var/lib/cloudflare-warp /usr/local/share/xray

# Xray 路由规则需要 geoip.dat / geosite.dat（国内直连等）
ARG GEO_URLS="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release https://ghproxy.com/https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
RUN set -eux; \
    for GEO_URL in $GEO_URLS; do \
      echo "Trying: $GEO_URL"; \
      if curl -fsSL --retry 6 --retry-delay 2 --retry-all-errors --connect-timeout 10 --max-time 120 "${GEO_URL}/geoip.dat" -o /usr/local/share/xray/geoip.dat && \
         curl -fsSL --retry 6 --retry-delay 2 --retry-all-errors --connect-timeout 10 --max-time 120 "${GEO_URL}/geosite.dat" -o /usr/local/share/xray/geosite.dat; then \
        exit 0; \
      fi; \
    done; \
    echo "Failed to download geoip.dat/geosite.dat from all GEO_URLS=$GEO_URLS" >&2; \
    exit 1

COPY --from=builder /cfwarpxray /usr/local/bin/cfwarpxray
# Zero Trust 配置从 builder 阶段复制，确保任意构建上下文下镜像内都有该文件；可用 -v 挂载覆盖
COPY --from=builder /app/config/zero-trust.yaml /etc/cfwarpxray/zero-trust.yaml

EXPOSE 16666 16667 16668 16665

CMD ["/usr/local/bin/cfwarpxray"]
