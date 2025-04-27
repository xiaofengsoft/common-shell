#!/bin/bash

set -e

# 默认参数
DEFAULT_WORKDIR="/tmp/docker-to-crictl"
FILTER=""
NAMESPACE="k8s.io"
CLEANUP=false
INTERACTIVE=false

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help            显示帮助信息"
    echo "  -w, --workdir DIR     设置工作目录 (默认: $DEFAULT_WORKDIR)"
    echo "  -f, --filter PATTERN  按模式过滤镜像"
    echo "  -n, --namespace NS    指定导入的命名空间 (默认: k8s.io)"
    echo "  -c, --cleanup         处理完成后清理临时文件"
    echo "  -i, --interactive     交互式模式"
    exit 0
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -w|--workdir) WORKDIR="$2"; shift ;;
        -f|--filter) FILTER="$2"; shift ;;
        -n|--namespace) NAMESPACE="$2"; shift ;;
        -c|--cleanup) CLEANUP=true ;;
        -i|--interactive) INTERACTIVE=true ;;
        *) echo "未知参数: $1"; show_help ;;
    esac
    shift
done

# 交互式输入模式
if [ "$INTERACTIVE" = true ]; then
    read -p "请输入工作目录 [默认: $DEFAULT_WORKDIR]: " USER_WORKDIR
    WORKDIR=${USER_WORKDIR:-$DEFAULT_WORKDIR}
    
    read -p "输入镜像过滤模式 (留空导出所有镜像): " FILTER
    
    read -p "输入目标命名空间 [默认: k8s.io]: " USER_NAMESPACE
    NAMESPACE=${USER_NAMESPACE:-k8s.io}
    
    read -p "处理完成后是否清理临时文件? (y/n) [默认: n]: " CLEANUP_CHOICE
    if [[ $CLEANUP_CHOICE == "y" || $CLEANUP_CHOICE == "Y" ]]; then
        CLEANUP=true
    fi
else
    # 如果没有通过参数指定工作目录，使用默认值
    WORKDIR=${WORKDIR:-$DEFAULT_WORKDIR}
fi

echo "📋 配置信息:"
echo "  - 工作目录: $WORKDIR"
echo "  - 命名空间: $NAMESPACE"
echo "  - 过滤模式: ${FILTER:-无}"
echo "  - 清理临时文件: $CLEANUP"

# 设置临时目录
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "📦 正在导出本地 Docker 镜像..."

# 获取镜像的完整名称（包括标签）
if [ -z "$FILTER" ]; then
    IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>')
else
    echo "🔍 使用过滤器: $FILTER"
    IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | grep "$FILTER")
fi

if [ -z "$IMAGES" ]; then
    echo "⚠️ 未找到任何有效的 Docker 镜像。"
    exit 1
fi

echo "🔎 找到以下镜像:"
echo "$IMAGES" | sed 's/^/   /'
read -p "是否继续导出这些镜像? (y/n) [默认: y]: " CONFIRM
if [[ $CONFIRM == "n" || $CONFIRM == "N" ]]; then
    echo "❌ 操作已取消。"
    exit 0
fi

# 遍历每个镜像，导出并导入到 containerd
for IMAGE in $IMAGES; do
    # 替换镜像名称中的特殊字符以创建有效的文件名
    SAFE_IMAGE_NAME=$(echo "$IMAGE" | sed 's/[^a-zA-Z0-9_.-]/_/g')
    TAR_FILE="${SAFE_IMAGE_NAME}.tar"

    echo "🔄 正在处理镜像: $IMAGE"
    echo "   ➤ 导出为: $TAR_FILE"

    # 导出 Docker 镜像为 tar 文件
    docker save -o "$TAR_FILE" "$IMAGE"

    echo "   ➤ 导入到 containerd（$NAMESPACE 命名空间）..."
    # 导入到 containerd 的指定命名空间
    sudo ctr -n "$NAMESPACE" images import "$TAR_FILE"

    echo "✅ 镜像 $IMAGE 已成功导入。"
done

echo "🎉 所有镜像已成功导入到 containerd。"

# 清理临时文件
if [ "$CLEANUP" = true ]; then
    echo "🧹 清理临时文件..."
    rm -rf "$WORKDIR"
    echo "✅ 临时文件已清理。"
fi