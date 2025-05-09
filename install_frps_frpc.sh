#!/bin/bash

# 一体化FRP服务端/客户端管理脚本
# 适用于CentOS Stream9系统
# 版本：v1.2

stty erase ^? 2>/dev/null  # 兼容不同终端的退格键

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误：该脚本必须以root用户身份运行${RESET}"
        exit 1
    fi
}

# 全局配置
FRP_VERSION="0.62.1"
INSTALL_DIR="/usr/local/frp"
CONFIG_DIR="${INSTALL_DIR}/conf"
SERVICE_DIR="/etc/systemd/system"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"

# 初始化目录
init_directories() {
    mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}"
}

# 主菜单
show_main_menu() {
    clear
    echo -e "${BLUE}==================================================${RESET}"
    echo -e "FRP 一体化管理脚本 v1.2"
    echo -e "${BLUE}==================================================${RESET}"
    echo "1) 安装/配置 FRP 服务端"
    echo "2) 安装/配置 FRP 客户端"
    echo "3) 端口映射管理"
    echo "4) 查看服务状态"
    echo "5) 卸载FRP"
    echo "6) 退出脚本"
    echo -e "${BLUE}==================================================${RESET}"
    read -e -p "请输入数字选择(默认1): " MAIN_MODE
    MAIN_MODE=${MAIN_MODE:-1}
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装基础依赖...${RESET}"
    dnf install -y wget tar dos2unix > /dev/null 2>&1
}

# 下载和解压FRP
prepare_install() {
    cd "${INSTALL_DIR}" || exit 1
    if [ -f "frp_${FRP_VERSION}_linux_amd64.tar.gz" ]; then
        echo -e "${YELLOW}检测到已下载文件，跳过下载...${RESET}"
    else
        echo -e "${YELLOW}正在下载FRP v${FRP_VERSION}...${RESET}"
        if ! wget -q "${DOWNLOAD_URL}"; then
            echo -e "${RED}错误：文件下载失败，请检查网络连接${RESET}"
            exit 1
        fi
    fi
    tar -zxvf "frp_${FRP_VERSION}_linux_amd64.tar.gz" > /dev/null 2>&1
}

# 安装服务端
install_frps() {
    echo -e "${BLUE}================ FRP 服务端配置 ================${RESET}"
    read -e -p "设置认证token (默认: adc123): " TOKEN
    read -e -p "设置Web管理密码 (默认: adc123): " PASSWORD
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
    cat > "${CONFIG_DIR}/frps.toml" << EOF
bindPort = ${BIND_PORT}
auth.token = "${TOKEN}"
vhostHTTPPort = ${HTTP_PORT}
webServer.addr = "0.0.0.0"
webServer.port = ${WEB_PORT}
webServer.user = "admin"
webServer.password = "${PASSWORD}"
EOF

    # 创建系统服务
    cat > "${SERVICE_DIR}/frps.service" << EOF
[Unit]
Description=FRP Server Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64
ExecStart=${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64/frps -c ${CONFIG_DIR}/frps.toml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now frps > /dev/null 2>&1

    if systemctl is-active --quiet frps; then
        echo -e "\n${GREEN}FRP服务端安装成功！${RESET}"
        echo -e "[重要] 请在防火墙放行以下端口："
        echo -e "服务端口：${BLUE}${BIND_PORT}/TCP${RESET}"
        echo -e "HTTP代理：${BLUE}${HTTP_PORT}/TCP${RESET}"
        echo -e "管理端口：${BLUE}${WEB_PORT}/TCP${RESET}"
        echo -e "\n管理面板地址：${BLUE}http://服务器IP:${WEB_PORT}${RESET}"
        echo -e "登录账号：admin | 密码：${PASSWORD}"
    else
        echo -e "${RED}错误：服务启动失败，请检查日志：journalctl -u frps${RESET}"
        exit 1
    fi
}

# 安装客户端
install_frpc() {
    echo -e "${BLUE}================ FRP 客户端配置 ================${RESET}"
    read -e -p "服务器IP地址: " SERVER_IP
    read -e -p "认证token (与服务端一致): " TOKEN
    read -e -p "服务端口 (默认7000): " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}

    # 生成客户端基础配置
    cat > "${CONFIG_DIR}/frpc.toml" << EOF
serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${TOKEN}"
EOF

    # 创建系统服务
    cat > "${SERVICE_DIR}/frpc.service" << EOF
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=nobody
WorkingDirectory=${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64
ExecStart=${INSTALL_DIR}/frp_${FRP_VERSION}_linux_amd64/frpc -c ${CONFIG_DIR}/frpc.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now frpc > /dev/null 2>&1

    if systemctl is-active --quiet frpc; then
        echo -e "\n${GREEN}FRP客户端安装成功！${RESET}"
        echo -e "请使用端口映射管理功能添加映射"
    else
        echo -e "${RED}错误：服务启动失败，请检查日志：journalctl -u frpc${RESET}"
        exit 1
    fi
}

# 端口映射管理
manage_proxies() {
    while true; do
        clear
        echo -e "${BLUE}================ 端口映射管理 ================${RESET}"
        echo "1) 查看当前映射"
        echo "2) 添加新映射"
        echo "3) 删除现有映射"
        echo "4) 返回主菜单"
        read -e -p "请选择操作(默认1): " PROXY_ACTION
        PROXY_ACTION=${PROXY_ACTION:-1}

        case $PROXY_ACTION in
            1)
                show_current_proxies
                ;;
            2)
                add_proxy_mapping
                ;;
            3)
                delete_proxy_mapping
                ;;
            4)
                return 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${RESET}"
                sleep 1
                ;;
        esac
    done
}

# 显示当前映射
show_current_proxies() {
    clear
    echo -e "${BLUE}================ 当前端口映射 ================${RESET}"
    
    if [ -f "${CONFIG_DIR}/frpc.toml" ]; then
        echo -e "\n${GREEN}[客户端配置]${RESET}"
        grep -A 3 "\[proxies\]" "${CONFIG_DIR}/frpc.toml" | \
        awk '/name/{name=$3} /type/{type=$3} /localPort/{lp=$3} /remotePort/{rp=$3; printf "%-20s %-8s %-15s => %-15s\n", name, type, lp, rp}'
    else
        echo -e "${YELLOW}未找到客户端配置文件${RESET}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# 添加端口映射
add_proxy_mapping() {
    echo -e "${BLUE}================ 添加端口映射 ================${RESET}"
    read -e -p "请输入映射名称 (示例: web): " proxy_name
    read -e -p "选择协议类型 (tcp/udp, 默认tcp): " proxy_type
    read -e -p "请输入本地端口: " local_port
    read -e -p "请输入远程端口: " remote_port

    # 设置默认值
    proxy_type=${proxy_type:-tcp}
    proxy_name=${proxy_name:-proxy_$(date +%s)}

    # 验证输入
    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || ! [[ "$remote_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误：端口必须为数字${RESET}"
        sleep 1
        return
    fi

    # 追加配置
    cat >> "${CONFIG_DIR}/frpc.toml" << EOF

[[proxies]]
name = "${proxy_name}"
type = "${proxy_type}"
localIP = "127.0.0.1"
localPort = ${local_port}
remotePort = ${remote_port}
EOF

    # 重启服务生效
    systemctl restart frpc
    echo -e "${GREEN}成功添加映射：${proxy_name} ${proxy_type} ${local_port}->${remote_port}${RESET}"
    sleep 1
}

# 删除端口映射
delete_proxy_mapping() {
    clear
    echo -e "${BLUE}================ 删除端口映射 ================${RESET}"
    if [ ! -f "${CONFIG_DIR}/frpc.toml" ]; then
        echo -e "${YELLOW}未找到客户端配置文件${RESET}"
        sleep 1
        return
    fi
    
    mapfile -t proxy_lines < <(grep -n "\[proxies\]" "${CONFIG_DIR}/frpc.toml" -A 4)
    
    echo -e "${GREEN}当前配置的端口映射：${RESET}"
    counter=1
    for i in "${!proxy_lines[@]}"; do
        if [[ "${proxy_lines[$i]}" == *"name"* ]]; then
            name=$(echo "${proxy_lines[$i]}" | cut -d'"' -f2)
            type=$(echo "${proxy_lines[$((i+1))]}" | cut -d'"' -f2)
            localPort=$(echo "${proxy_lines[$((i+2))]}" | awk '{print $3}')
            remotePort=$(echo "${proxy_lines[$((i+3))]}" | awk '{print $3}')
            printf "%-4s %-20s %-8s %-15s => %-15s\n" "$counter" "$name" "$type" "$localPort" "$remotePort"
            ((counter++))
        fi
    done

    read -e -p "请输入要删除的映射序号 (0取消): " del_num
    if [ "$del_num" -eq 0 ]; then return; fi

    # 计算要删除的行号范围
    start_line=$(echo "${proxy_lines[0]}" | cut -d: -f1)
    target_line=$((start_line + (del_num-1)*5 + 1))
    
    if sed -n "${target_line}p" "${CONFIG_DIR}/frpc.toml" | grep -q "name ="; then
        sed -i "${target_line},+4d" "${CONFIG_DIR}/frpc.toml"
        systemctl restart frpc
        echo -e "${GREEN}成功删除第${del_num}个映射配置${RESET}"
    else
        echo -e "${RED}错误：无效的序号${RESET}"
    fi
    sleep 1
}

# 查看服务状态
show_service_status() {
    clear
    echo -e "${BLUE}================ 服务状态 ================${RESET}"
    (echo -e "${GREEN}服务端状态：${RESET}" && systemctl status frps -l) || echo -e "${YELLOW}FRP服务端未安装${RESET}"
    echo ""
    (echo -e "${GREEN}客户端状态：${RESET}" && systemctl status frpc -l) || echo -e "${YELLOW}FRP客户端未安装${RESET}"
    read -n 1 -s -r -p "按任意键返回..."
}

# 卸载FRP
uninstall_frp() {
    echo -e "${BLUE}================ 卸载FRP ================${RESET}"
    systemctl stop frps frpc 2>/dev/null
    systemctl disable frps frpc 2>/dev/null
    rm -f "${SERVICE_DIR}/frps.service" "${SERVICE_DIR}/frpc.service"
    rm -rf "${INSTALL_DIR}"
    echo -e "${GREEN}FRP已完全卸载${RESET}"
    sleep 1
}

# 主程序流程
main() {
    check_root
    init_directories
    while true; do
        show_main_menu
        case $MAIN_MODE in
            1)
                install_dependencies
                prepare_install
                install_frps
                ;;
            2)
                install_dependencies
                prepare_install
                install_frpc
                ;;
            3)
                manage_proxies
                ;;
            4)
                show_service_status
                ;;
            5)
                uninstall_frp
                ;;
            6)
                echo -e "\n${YELLOW}感谢使用，再见！${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}错误：无效的选择${RESET}"
                sleep 1
                ;;
        esac
    done
}

# 启动主程序
main
