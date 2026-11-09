#!/usr/bin/env bash
# ============================================================================
# A 服务器 (中控机) 一键初始化与连通性自检脚本
# 用法: bash scripts/init-control-node.sh
# ============================================================================
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_DIR="$HOME/.ssh"
KEYS_DIR="$SSH_DIR/keys"
SOCKETS_DIR="$SSH_DIR/sockets"

echo ">>> [1/4] 初始化 ~/.ssh 目录结构与安全权限..."
mkdir -p "$KEYS_DIR" "$SOCKETS_DIR"
chmod 700 "$SSH_DIR" "$KEYS_DIR" "$SOCKETS_DIR"

# 如果 keys 目录下已经有私钥文件，统一修正权限为 600
if compgen -G "$KEYS_DIR/*" > /dev/null; then
    chmod 600 "$KEYS_DIR"/*
    echo "    已将 $KEYS_DIR/ 下的所有密钥权限修正为 600"
else
    echo "    提示: 请将 B~F 服务器的私钥放入 $KEYS_DIR/ 目录下"
fi

echo ">>> [2/4] 检查 ~/.ssh/config 配置..."
if [ ! -f "$SSH_DIR/config" ]; then
    cp "$WORKSPACE_DIR/ssh_config.example" "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"
    echo "    已从模板创建 ~/.ssh/config，请编辑其中的真实 IP 和密钥文件名！"
else
    chmod 600 "$SSH_DIR/config"
    echo "    检测到已存在 ~/.ssh/config (权限已确保为 600)"
fi

echo ">>> [3/4] 检查 Ansible 是否安装..."
if command -v ansible >/dev/null 2>&1; then
    echo "    Ansible 已安装: $(ansible --version | head -n 1)"
else
    echo "    未检测到 Ansible，建议在 A 服务器执行安装："
    echo "    Ubuntu/Debian: sudo apt update && sudo apt install -y ansible"
    echo "    或使用 pipx/uv: uv tool install ansible-core"
fi

echo ">>> [4/4] 测试 B C D E F 节点 SSH 连通性..."
NODES=("node-b" "node-c" "node-d" "node-e" "node-f")
for node in "${NODES[@]}"; do
    printf "    测试 %-8s ... " "$node"
    # 注意使用单引号包裹远端命令，确保 $(hostname) 在远端节点执行而非本机展开
    if timeout 8s ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" 'echo "OK (远端主机: $(hostname), 用户: $(whoami))"' 2>/dev/null; then
        :
    else
        echo "未连通 (请检查 ~/.ssh/config 中的 IP 和 $KEYS_DIR 下的密钥)"
    fi
done

echo ""
echo "✅ 初始化检查完成！后续请在 $WORKSPACE_DIR 目录下启动 AGY CLI 进行运维。"
