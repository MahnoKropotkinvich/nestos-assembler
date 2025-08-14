#!/bin/bash
set -e 
set -o pipefail
# 默认的 OCI 运行时
RUNTIME="docker"
arch=$(uname -m)

# 解析命令行选项
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -r|--runtime)
      RUNTIME="$2"
      shift # 移过参数名
      shift # 移过参数值
      ;;
    -a|--arch)
      arch="$2"
      shift
      shift
      ;;
    *)
      # 未知选项
      echo "未知选项: $1"
      exit 1
      ;;
  esac
done

# 验证运行时
if [[ "$RUNTIME" != "docker" && "$RUNTIME" != "podman" ]]; then
  echo "无效的运行时: '$RUNTIME'. 请使用 'docker' 或 'podman'."
  exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "请先安装 curl"
    exit 1
fi
if ! command -v xz &>/dev/null; then
    echo "请先安装 xz"
    exit 1
fi
if ! command -v "$RUNTIME" &>/dev/null; then
    echo "未找到 '$RUNTIME'，请先安装它。"
    exit 1
fi

echo "将使用 '$RUNTIME' 导入镜像..."
# 下载、解压并导入镜像
curl -L "https://repo.openeuler.org/openEuler-24.03-LTS-SP2/docker_img/${arch}/openEuler-docker.${arch}.tar.xz" | xz -d | "$RUNTIME" load
echo "镜像导入完成 将启动构建"
"$RUNTIME" build -t nestos-assembler:latest .
echo "镜像构建完成 名称:nestos-assembler"
