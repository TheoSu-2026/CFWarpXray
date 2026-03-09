#!/bin/bash
set -euo pipefail

# 若需指定仓库，可运行: REPO_URL=https://github.com/你的用户名/CFWarpXray.git ./deploy.sh
REPO_URL="${REPO_URL:-https://github.com/TheoSu-2026/CFWarpXray.git}"

# 检测操作系统（必须在 INSTALL_DIR 默认值之前）
OS=$(uname -s)

# Mac 上使用的 Docker 后端：desktop（Docker Desktop）或 colima
DOCKER_BACKEND="${DOCKER_BACKEND:-desktop}"

if [ "$OS" = "Darwin" ]; then
    INSTALL_DIR="${INSTALL_DIR:-$HOME/CFWarpXray}"
else
    INSTALL_DIR="${INSTALL_DIR:-/opt/CFWarpXray}"
fi

# ── 工具函数 ──────────────────────────────────────────────

# 获取 CPU 架构（统一为 Docker 格式）
get_arch() {
    case "$(uname -m)" in
        x86_64)        echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l)        echo "armhf" ;;
        *)             echo "$(uname -m)" ;;
    esac
}

# 退出时清理临时文件
TMP_JSON=""
cleanup() {
    [ -n "$TMP_JSON" ] && rm -f "$TMP_JSON"
}
trap cleanup EXIT

# 在 Mac 上重启 Docker 并等待就绪（支持 Docker Desktop 与 Colima）
restart_docker_mac() {
    if [ "${DOCKER_BACKEND:-desktop}" = "colima" ]; then
        echo "    重启 Colima..."
        colima stop 2>/dev/null || true
        sleep 2
        colima start
    else
        echo "    重启 Docker Desktop..."
        osascript -e 'quit app "Docker"' 2>/dev/null || true
        sleep 2
        open -a Docker
    fi
    echo "    等待 Docker 启动（最多 60 秒）..."
    local i
    for i in {1..60}; do
        if docker info &>/dev/null 2>&1; then
            echo "    Docker 已就绪"
            return 0
        fi
        sleep 1
    done
    echo "    错误：Docker 启动超时，请手动启动后重试"
    exit 1
}

# 检查 docker compose 插件（v2）
check_compose() {
    if ! docker compose version &>/dev/null 2>&1; then
        echo "    错误：需要 docker compose 插件（v2），请更新 Docker 至最新版本"
        exit 1
    fi
}

# 检测本机公网 IP（用于 VLESS 链接），失败返回空（Mac 多为 NAT 无公网 IP，不依赖此函数）
get_public_ip() {
    local ip
    for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip=$(curl -s --connect-timeout 3 -m 5 "$url" 2>/dev/null | tr -d '\r\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        [ -n "$ip" ] && echo "$ip" && return 0
    done
    return 1
}

# 检测本机局域网 IP（Mac/NAT 环境用，VLESS 链接填本机 LAN 地址供内网使用）
get_lan_ip() {
    local ip
    if [ "$(uname -s)" = "Darwin" ]; then
        ip=$(ipconfig getifaddr en0 2>/dev/null) || ip=$(ipconfig getifaddr en1 2>/dev/null)
        [ -n "$ip" ] && echo "$ip" && return 0
        ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
    else
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        [ -z "$ip" ] && ip=$(ip -4 route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')
    fi
    [ -n "$ip" ] && echo "$ip" && return 0
    return 1
}

# ── [1/5] 检查环境 ────────────────────────────────────────

echo "[1/5] 检查环境..."

if [ -f "Dockerfile" ] && [ -f "docker-compose.yml" ]; then
    INSTALL_DIR="$(pwd)"
    echo "    使用当前目录: $INSTALL_DIR"
else
    # 安装 git（如需要）
    if ! command -v git &>/dev/null; then
        echo "    安装 git..."
        if [ "$OS" = "Darwin" ]; then
            if command -v brew &>/dev/null; then
                brew install git
            else
                echo "    错误：未找到 Homebrew，请先安装：https://brew.sh"
                exit 1
            fi
        else
            sudo apt-get update -qq
            sudo apt-get install -y git
        fi
    fi

    echo "    将克隆仓库到: $INSTALL_DIR"
    if [ "$OS" = "Darwin" ]; then
        mkdir -p "$(dirname "$INSTALL_DIR")"
        if [ -d "$INSTALL_DIR/.git" ]; then
            echo "    目录已存在，拉取最新..."
            DEPLOY_BACKUP="/tmp/cfwarpxray-deploy-$$"
            mkdir -p "$DEPLOY_BACKUP"
            [ -f "$INSTALL_DIR/config/zero-trust.yaml" ] && cp "$INSTALL_DIR/config/zero-trust.yaml" "$DEPLOY_BACKUP"
            [ -f "$INSTALL_DIR/.env" ] && cp "$INSTALL_DIR/.env" "$DEPLOY_BACKUP"
            git -C "$INSTALL_DIR" checkout -- config/zero-trust.yaml 2>/dev/null || true
            rm -f "$INSTALL_DIR/.env"
            if ! git -C "$INSTALL_DIR" pull; then
                echo "    警告：git pull 失败，尝试 git reset --hard origin/main"
                git -C "$INSTALL_DIR" fetch origin
                git -C "$INSTALL_DIR" reset --hard origin/main
            fi
            mkdir -p "$INSTALL_DIR/config"
            [ -f "$DEPLOY_BACKUP/zero-trust.yaml" ] && cp "$DEPLOY_BACKUP/zero-trust.yaml" "$INSTALL_DIR/config/zero-trust.yaml"
            [ -f "$DEPLOY_BACKUP/.env" ] && cp "$DEPLOY_BACKUP/.env" "$INSTALL_DIR/.env"
            rm -rf "$DEPLOY_BACKUP"
        elif [ -d "$INSTALL_DIR" ]; then
            echo "    目录已存在但非 git 仓库，清空后重新克隆..."
            rm -rf "$INSTALL_DIR"
            git clone "$REPO_URL" "$INSTALL_DIR"
        else
            git clone "$REPO_URL" "$INSTALL_DIR"
        fi
    else
        sudo mkdir -p "$(dirname "$INSTALL_DIR")"
        if [ -d "$INSTALL_DIR/.git" ]; then
            echo "    目录已存在，拉取最新..."
            DEPLOY_BACKUP="/tmp/cfwarpxray-deploy-$$"
            mkdir -p "$DEPLOY_BACKUP"
            [ -f "$INSTALL_DIR/config/zero-trust.yaml" ] && sudo cp "$INSTALL_DIR/config/zero-trust.yaml" "$DEPLOY_BACKUP"
            [ -f "$INSTALL_DIR/.env" ] && sudo cp "$INSTALL_DIR/.env" "$DEPLOY_BACKUP"
            sudo git -C "$INSTALL_DIR" checkout -- config/zero-trust.yaml 2>/dev/null || true
            sudo rm -f "$INSTALL_DIR/.env"
            if ! sudo git -C "$INSTALL_DIR" pull; then
                echo "    警告：git pull 失败，尝试 git reset --hard origin/main"
                sudo git -C "$INSTALL_DIR" fetch origin
                sudo git -C "$INSTALL_DIR" reset --hard origin/main
            fi
            sudo mkdir -p "$INSTALL_DIR/config"
            [ -f "$DEPLOY_BACKUP/zero-trust.yaml" ] && sudo cp "$DEPLOY_BACKUP/zero-trust.yaml" "$INSTALL_DIR/config/zero-trust.yaml"
            [ -f "$DEPLOY_BACKUP/.env" ] && sudo cp "$DEPLOY_BACKUP/.env" "$INSTALL_DIR/.env"
            rm -rf "$DEPLOY_BACKUP"
        elif [ -d "$INSTALL_DIR" ]; then
            echo "    目录已存在但非 git 仓库，清空后重新克隆..."
            sudo rm -rf "$INSTALL_DIR"
            sudo git clone "$REPO_URL" "$INSTALL_DIR"
        else
            sudo git clone "$REPO_URL" "$INSTALL_DIR"
        fi
    fi
fi

# ── [2/5] 检查 Docker ─────────────────────────────────────

echo "[2/5] 检查 Docker..."
if ! command -v docker &>/dev/null; then
    if [ "$OS" = "Darwin" ]; then
        echo ""
        echo "    未检测到 Docker，请先手动安装 Docker Desktop。"
        echo ""
        echo "    官网下载：https://www.docker.com/products/docker-desktop/"
        echo ""
        echo "    安装并启动 Docker Desktop 后，重新运行本脚本即可。"
        exit 1
    else
        # Linux：通过 Docker 官方 apt 源安装
        if [ -f /etc/os-release ]; then
            # shellcheck source=/dev/null
            . /etc/os-release
            case "$ID" in
                ubuntu) DOCKER_DISTRO=ubuntu ;;
                *)      DOCKER_DISTRO=debian ;;
            esac
            DOCKER_CODENAME="${VERSION_CODENAME:-$VERSION_ID}"
        else
            DOCKER_DISTRO=debian
            DOCKER_CODENAME=bookworm
        fi
        echo "    检测到 $DOCKER_DISTRO ($DOCKER_CODENAME)，使用对应 Docker 源"
        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo apt-get update -qq
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/$DOCKER_DISTRO/gpg" \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(get_arch) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$DOCKER_DISTRO $DOCKER_CODENAME stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -qq
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
else
    echo "    Docker 已安装"
fi

check_compose

# ── [3/5] 配置 Docker bridge 网段 ────────────────────────

echo "[3/5] 配置 Docker bridge 网段..."
# Cloudflare WARP 的 Exclude 列表包含 172.16.0.0/12，Docker 默认 bridge 172.17.0.0/16 在其中，
# 会导致容器内 WARP connectivity checks 失败。将 bridge 改到 192.168.220.0/24 避开该范围。

if [ "$OS" = "Darwin" ]; then
    DAEMON_JSON="$HOME/.docker/daemon.json"
else
    DAEMON_JSON="/etc/docker/daemon.json"
fi

if [ -f "$DAEMON_JSON" ] && grep -q '"bip"' "$DAEMON_JSON"; then
    echo "    Docker bridge 网段已配置，跳过"
else
    echo "    设置 Docker bridge 网段为 192.168.220.1/24"
    if [ -f "$DAEMON_JSON" ]; then
        # 已有 daemon.json，追加 bip 字段（用 python3 安全合并 JSON）
        # 临时文件写到 /tmp，trap EXIT 会自动清理
        TMP_JSON=$(mktemp /tmp/docker-daemon-XXXXXX.json)
        # Linux 下 /etc/docker/daemon.json 为 root 所有，用 sudo cat 读取再传给 python3
        if [ "$OS" = "Darwin" ]; then
            python3 - "$DAEMON_JSON" "$TMP_JSON" <<'PYEOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    cfg = json.load(f)
cfg["bip"] = "192.168.220.1/24"
with open(dst, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
            mv "$TMP_JSON" "$DAEMON_JSON"
        else
            sudo python3 - "$DAEMON_JSON" "$TMP_JSON" <<'PYEOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    cfg = json.load(f)
cfg["bip"] = "192.168.220.1/24"
with open(dst, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
            sudo mv "$TMP_JSON" "$DAEMON_JSON"
        fi
        TMP_JSON=""  # 已成功 mv，不需要 trap 再清理
    else
        if [ "$OS" = "Darwin" ]; then
            mkdir -p "$(dirname "$DAEMON_JSON")"
            echo '{"bip":"192.168.220.1/24"}' > "$DAEMON_JSON"
        else
            echo '{"bip":"192.168.220.1/24"}' | sudo tee "$DAEMON_JSON" > /dev/null
        fi
    fi

    echo "    重启 Docker 使网段生效..."
    if [ "$OS" = "Darwin" ]; then
        restart_docker_mac
    else
        sudo systemctl restart docker
    fi
fi

# ── [4/5] 构建镜像 ────────────────────────────────────────

echo "[4/5] 构建镜像..."
# 用数组避免路径含空格时 word-splitting 出错
if [ "$OS" = "Darwin" ]; then
    COMPOSE_CMD=(docker compose -f "$INSTALL_DIR/docker-compose.yml" --project-directory "$INSTALL_DIR")
else
    COMPOSE_CMD=(sudo docker compose -f "$INSTALL_DIR/docker-compose.yml" --project-directory "$INSTALL_DIR")
fi

"${COMPOSE_CMD[@]}" build

# ── [4.5/5] Zero Trust 配置引导 ─────────────────────────────

echo "[4.5/5] Zero Trust 配置..."
echo ""
echo "  是否使用 Zero Trust 团队模式？"
echo "  - 使用团队模式时，程序将用您提供的凭证连接 Cloudflare WARP，并受 Zero Trust 策略管控。"
echo "  - 选择「是」并填写以下三项后，程序将以 Zero Trust 团队模式运行，受组织策略管控。"
echo "  - 选择「否」将以个人 WARP 模式运行（无需凭证，直接连接 Cloudflare WARP 个人服务）。"
echo "  - 选择「是」前，您须已具备："
echo "    1) Cloudflare Zero Trust 团队（Cloudflare Zero Trust 控制台）；"
echo "    2) 已在后台创建 Service Auth 凭证（设备注册 / Device enrollment → Service Auth），"
echo "       并取得 organization（团队名）、auth_client_id、auth_client_secret 三项。"
echo ""
read -r -p "  是否使用 Zero Trust 团队模式？(y/n，默认 n): " ZT_ENABLE
echo ""
ZT_ENABLE="${ZT_ENABLE:-n}"
ZT_ENABLE=$(printf '%s' "$ZT_ENABLE" | tr '[:upper:]' '[:lower:]')

ZERO_TRUST_YAML="$INSTALL_DIR/config/zero-trust.yaml"
if [ "$OS" != "Darwin" ] && [ "$INSTALL_DIR" != "$(pwd)" ]; then
    sudo mkdir -p "$INSTALL_DIR/config"
else
    mkdir -p "$INSTALL_DIR/config"
fi

case "$ZT_ENABLE" in
    y|yes)
        echo ""
        read -r -p "  请输入 Zero Trust 组织名 (team name)：" ZT_ORG
        read -r -p "  请输入 auth_client_id：" ZT_CID
        read -r -p "  请输入 auth_client_secret：" ZT_SECRET
        ZT_ORG=$(echo "$ZT_ORG" | sed 's/"/\\"/g')
        ZT_CID=$(echo "$ZT_CID" | sed 's/"/\\"/g')
        ZT_SECRET=$(echo "$ZT_SECRET" | sed 's/"/\\"/g')
        cat > /tmp/zero-trust-deploy.yaml <<ZTYAML
# 由 deploy.sh 根据输入生成
enabled: true
organization: "$ZT_ORG"
auth_client_id: "$ZT_CID"
auth_client_secret: "$ZT_SECRET"
service_mode: "proxy"
proxy_port: 40000
auto_connect: 1
ZTYAML
        if [ "$OS" != "Darwin" ] && [ "$INSTALL_DIR" != "$(pwd)" ]; then
            sudo cp /tmp/zero-trust-deploy.yaml "$ZERO_TRUST_YAML"
        else
            cp /tmp/zero-trust-deploy.yaml "$ZERO_TRUST_YAML"
        fi
        rm -f /tmp/zero-trust-deploy.yaml
        echo "    已写入 ${ZERO_TRUST_YAML}（enabled: true）"
        ;;
    *)
        cat > /tmp/zero-trust-deploy.yaml <<'ZTYAML'
# 由 deploy.sh 生成，未启用 Zero Trust 团队模式，使用个人 WARP
enabled: false
organization: ""
auth_client_id: ""
auth_client_secret: ""
service_mode: "proxy"
proxy_port: 40000
auto_connect: 1
ZTYAML
        if [ "$OS" != "Darwin" ] && [ "$INSTALL_DIR" != "$(pwd)" ]; then
            sudo cp /tmp/zero-trust-deploy.yaml "$ZERO_TRUST_YAML"
        else
            cp /tmp/zero-trust-deploy.yaml "$ZERO_TRUST_YAML"
        fi
        rm -f /tmp/zero-trust-deploy.yaml
        echo "    已写入 ${ZERO_TRUST_YAML}（个人 WARP 模式，enabled: false）"
        ;;
esac
echo ""

# ── [5/5] 启动容器 ────────────────────────────────────────

echo "[5/5] 启动容器..."
# VLESS 链接主机地址：Mac 多为 NAT 无公网 IP，用局域网地址；Linux 尝试公网 IP，失败可手动设
VLESS_HOST=""
if [ "$OS" = "Darwin" ]; then
    VLESS_HOST=$(get_lan_ip 2>/dev/null || echo "")
    [ -n "${VLESS_HOST:-}" ] && echo "    已检测局域网地址: ${VLESS_HOST}（VLESS 链接将使用该地址，供本机/内网使用）"
else
    VLESS_HOST=$(get_public_ip 2>/dev/null || echo "")
    [ -n "${VLESS_HOST:-}" ] && echo "    已检测公网 IP: ${VLESS_HOST}（VLESS 链接将使用该地址）"
fi
if [ -n "${VLESS_HOST:-}" ]; then
    echo "WARP_XRAY_VLESS_HOST=${VLESS_HOST}" > "$INSTALL_DIR/.env"
else
    echo "    未检测到可用地址，可稍后在 $INSTALL_DIR/.env 中设置 WARP_XRAY_VLESS_HOST"
fi
"${COMPOSE_CMD[@]}" up -d

# 等待容器稳定后显示状态
sleep 3
"${COMPOSE_CMD[@]}" ps

echo ""
echo "部署完成。"
echo "  - 状态: ${COMPOSE_CMD[*]} ps"
echo "  - 端口: 16666 (VLESS), 16667 (HTTP), 16668 (SOCKS5)"
echo ""
echo "正在跟进容器日志（Ctrl+C 退出）..."
"${COMPOSE_CMD[@]}" logs -f
