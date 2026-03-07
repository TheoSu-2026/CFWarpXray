#!/bin/bash
set -e

# 若需指定仓库，可运行: REPO_URL=https://github.com/你的用户名/CFWarpXray.git ./deploy.sh
REPO_URL="${REPO_URL:-https://github.com/TheoSu-2026/CFWarpXray.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/CFWarpXray}"

echo "[1/4] 检查环境..."

# 若当前目录已有 Dockerfile 和 docker-compose.yml，则直接使用当前目录
if [ -f "Dockerfile" ] && [ -f "docker-compose.yml" ]; then
    INSTALL_DIR="$(pwd)"
    echo "    使用当前目录: $INSTALL_DIR"
else
    if ! command -v git &>/dev/null; then
        echo "    安装 git..."
        sudo apt-get update -qq
        sudo apt-get install -y git
    fi
    echo "    将克隆仓库到: $INSTALL_DIR"
    sudo mkdir -p "$(dirname "$INSTALL_DIR")"
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo "    目录已存在，拉取最新..."
        sudo git -C "$INSTALL_DIR" pull
    else
        sudo git clone "$REPO_URL" "$INSTALL_DIR"
    fi
fi

echo "[2/4] 检查 Docker..."
if ! command -v docker &>/dev/null; then
    echo "    安装 Docker..."
    # 根据系统自动选择 Docker 官方源：Ubuntu 用 ubuntu，其余（Debian/Raspbian 等）用 debian
    if [ -f /etc/os-release ]; then
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
    # 先移除可能存在的错误 Docker 源，避免 apt-get update 报 404 并退出
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$DOCKER_DISTRO/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_DISTRO $DOCKER_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "    Docker 已安装"
fi

echo "[3/4] 构建镜像..."
sudo docker compose -f "$INSTALL_DIR/docker-compose.yml" --project-directory "$INSTALL_DIR" build

echo "[4/4] 启动容器..."
sudo docker compose -f "$INSTALL_DIR/docker-compose.yml" --project-directory "$INSTALL_DIR" up -d

echo ""
echo "部署完成。"
echo "  - 状态: sudo docker compose -f $INSTALL_DIR/docker-compose.yml --project-directory $INSTALL_DIR ps"
echo "  - 日志: sudo docker compose -f $INSTALL_DIR/docker-compose.yml --project-directory $INSTALL_DIR logs -f"
echo "  - 端口: 16666, 16667"