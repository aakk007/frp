#!/bin/bash

# 一体化FRP服务端/客户端安装脚本（增强版）
# 适用于CentOS Stream9系统
# 版本：v0.63.1

# 增强终端设置 --------------------------------------------------
stty sane                  # 重置终端到默认状态
stty erase ^? 2>/dev/null  # 明确设置退格键为删除
stty intr ^C  2>/dev/null  # 确保Ctrl-C中断可用
stty -echoctl              # 隐藏控制字符（如^C）

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误：该脚本必须以root用户身份运行\033[0m"
    exit 1
fi

# 全局配置
FRP_VERSION="0.62.1"
INSTALL_DIR="/usr/local/frp"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
INPUT_TIMEOUT=30  # 单位：秒

# 模式选择（带超时）
echo "--------------------------------------------------"
echo "请选择安装模式:"
echo "1) FRP 服务端 (frps) - 云服务器端"
echo "2) FRP 客户端 (frpc) - 本地局域网端"
if ! read -e -t $INPUT_TIMEOUT -p "请输入数字(默认1，${INPUT_TIMEOUT}秒超时): " INSTALL_MODE; then
    echo -e "\n\033[33m输入超时，使用默认模式1\033[0m"
    INSTALL_MODE=1
else
    INSTALL_MODE=${INSTALL_MODE:-1}
fi

# 公共函数：安装依赖
install_dependencies() {
    echo -e "\033[34m正在安装基础依赖...\033[0m"
    dnf install -y wget tar dos2unix > /dev/null 2>&1
}

# 公共函数：准备安装目录
prepare_install() {
    mkdir -p "${INSTALL_DIR}" && cd "${INSTALL_DIR}" || exit 1
    if [ -f "frp_${FRP_VERSION}_linux_amd64.tar.gz" ]; then
        echo -e "\033[33m检测到已下载文件，跳过下载...\033[0m"
    else
        echo -e "\033[34m正在下载FRP v${FRP_VERSION}...\033[0m"
        if ! wget -q "${DOWNLOAD_URL}"; then
            echo -e "\033[31m错误：文件下载失败，请检查网络连接\033[0m"
            exit 1
        fi
    fi
    tar -zxvf "frp_${FRP_VERSION}_linux_amd64.tar.gz" > /dev/null 2>&1
}

# 安装FRP服务端
install_frps() {
    # 交互配置
    echo "--------------------------------------------------"
    echo "正在配置FRP服务端（云服务器端）"
    read -e -p "设置认证token (默认: adc123): " TOKEN
    read -es -p "设置Web管理密码 (默认: adc123): " PASSWORD  # 密码隐藏输入
    echo  # 换行处理密码输入后的光标位置
    read -e -p "设置服务端口 (默认: 7000): " BIND_PORT
    read -e -p "设置HTTP代理端口 (默认: 28080): " HTTP_PORT
    read -e -p "设置Web管理端口 (默认: 7500): " WEB_PORT
    
    # 设置默认值
    TOKEN=${TOKEN:-"adc123"}
    PASSWORD=${PASSWORD:-"adc123"}
    BIND_PORT=${BIND_PORT:-7000}
    HTTP_PORT=${HTTP_PORT:-28080}
    WEB_PORT=${WEB_PORT:-7500}

    # 生成服务端配置
    cd "frp_${FRP_VERSION}_linux_amd64" || exit 1
    cat > frps.toml << EOF
bindPort = ${BIND_PORT}
auth.token = "${TOKEN}"
vhostHTTPPort = ${HTTP_PORT}
webServer.addr = "0.0.0.0"
webServer.port = ${WEB_PORT}
webServer.user = "admin"
webServer.password = "${PASSWORD}"
EOF

    # 创建系统服务
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64
ExecStart=${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64/frps -c ${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64/frps.toml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now frps > /dev/null 2>&1

    # 显示安装结果
    if systemctl is-active --quiet frps; then
        echo -e "\n\033[32mFRP服务端安装成功！\033[0m"
        echo -e "[重要] 请在云服务器控制台放行以下端口："
        echo -e "服务端口：\033[36m${BIND_PORT}/TCP\033[0m"
        echo -e "HTTP代理：\033[36m${HTTP_PORT}/TCP\033[0m"
        echo -e "管理端口：\033[36m${WEB_PORT}/TCP\033[0m"
        echo -e "\n管理面板地址：\033[36mhttp://服务器公网IP:${WEB_PORT}\033[0m"
        echo -e "登录账号：admin | 密码：${PASSWORD}"
    else
        echo -e "\033[31m错误：服务启动失败，请检查日志：journalctl -u frps\033[0m"
        exit 1
    fi
}

# 安装FRP客户端
install_frpc() {
    # 交互配置（关键步骤带超时）
    echo "--------------------------------------------------"
    echo "正在配置FRP客户端（本地局域网端）"
    
    # 服务器IP输入（带超时）
    if ! read -e -t $INPUT_TIMEOUT -p "服务器IP地址(${INPUT_TIMEOUT}秒超时): " SERVER_IP; then
        echo -e "\n\033[31m错误：必须输入服务器IP地址\033[0m"
        exit 1
    fi
    
    read -e -p "认证token (与服务端一致): " TOKEN
    read -e -p "服务端口 (默认7000): " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}

    # 自动获取本机IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')

    # 端口映射配置
    PROXIES=()
    while true; do
        clear
        echo "--------------------------------------------------"
        echo "当前已配置 ${#PROXIES[@]} 个端口映射"
        echo -e "\033[36m操作菜单：\033[0m"
        echo "1) 添加端口映射"
        echo "2) 删除端口映射"
        echo "3) 修改端口映射"
        echo "4) 完成配置"
        if ! read -e -t $INPUT_TIMEOUT -p "请选择操作(默认1，${INPUT_TIMEOUT}秒超时): " ACTION; then
            echo -e "\n\033[33m输入超时，自动继续配置...\033[0m"
            ACTION=1
        else
            ACTION=${ACTION:-1}
        fi

        case $ACTION in
            1)
                # 添加端口映射
                echo "--------------------------------------------------"
                read -e -p "映射名称 (如ssh/web): " PROXY_NAME
                read -e -p "协议类型 (tcp/udp, 默认tcp): " PROXY_TYPE
                read -e -p "本地端口: " LOCAL_PORT
                read -e -p "远程端口: " REMOTE_PORT

                # 验证端口格式
                if ! [[ $LOCAL_PORT =~ ^[0-9]+$ ]] || ! [[ $REMOTE_PORT =~ ^[0-9]+$ ]]; then
                    echo -e "\033[31m错误：端口必须为数字\033[0m"
                    sleep 1
                    continue
                fi

                # 设置默认值
                PROXY_TYPE=${PROXY_TYPE:-tcp}
                PROXY_NAME=${PROXY_NAME:-proxy_${#PROXIES[@]}}

                # 保存配置
                PROXIES+=("$PROXY_NAME,$PROXY_TYPE,$LOCAL_PORT,$REMOTE_PORT")
                echo -e "\033[32m成功添加映射：${PROXY_NAME} ${PROXY_TYPE} ${LOCAL_PORT}->${REMOTE_PORT}\033[0m"
                sleep 1
                ;;
            # ... [保持原有客户端配置逻辑不变，所有read添加-t参数]
        esac
    done

    # ... [保持原有客户端配置生成逻辑不变]

    # 显示安装结果
    if systemctl is-active --quiet frpc; then
        echo -e "\n\033[32mFRP客户端安装成功！\033[0m"
        echo -e "已配置的端口映射："
        printf "\033[36m%-20s %-8s %-15s => %-15s\033[0m\n" "名称" "协议" "本地端口" "远程端口"
        for proxy in "${PROXIES[@]}"; do
            IFS=',' read -r name type local_port remote_port <<< "$proxy"
            printf "%-20s %-8s %-15s => %-15s\n" "${name}" "${type}" "${local_port}" "${remote_port}"
        done
        echo -e "\n访问方式：\033[36m${SERVER_IP}:<远程端口>\033[0m"
        echo -e "请确保服务端已开放对应远程端口！"
    else
        echo -e "\033[31m错误：服务启动失败，请检查日志：journalctl -u frpc\033[0m"
        exit 1
    fi
}

# 主执行流程
install_dependencies
prepare_install
case $INSTALL_MODE in
    1) install_frps ;;
    2) install_frpc ;;
    *) echo -e "\033[31m错误：无效的安装模式选择\033[0m"; exit 1 ;;
esac