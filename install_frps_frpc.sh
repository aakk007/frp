#!/bin/bash

# 一体化FRP服务端/客户端管理脚本
# 版本：v2.0
# 最后更新：2024-06-20
# 支持：CentOS Stream9

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

# --------------------------
# 主菜单系统
# --------------------------
show_main_menu() {
    clear
    echo -e "${BLUE}==================================================${RESET}"
    echo -e " FRP 一体化管理脚本 v2.0"
    echo -e "${BLUE}==================================================${RESET}"
    echo " 1) 安装/配置 FRP 服务端"
    echo " 2) 安装/配置 FRP 客户端"
    echo " 3) 端口映射管理"
    echo " 4) 查看服务状态"
    echo " 5) 卸载FRP"
    echo " 6) 退出脚本"
    echo -e "${BLUE}==================================================${RESET}"
    read -e -p "请输入数字选择 [1-6] (默认1): " MAIN_MODE
    MAIN_MODE=${MAIN_MODE:-1}
}

# --------------------------
# 依赖安装
# --------------------------
install_dependencies() {
    echo -e "${YELLOW}[+] 正在安装基础依赖...${RESET}"
    if ! dnf install -y wget tar dos2unix > /dev/null 2>&1; then
        echo -e "${RED}错误：依赖安装失败${RESET}"
        exit 1
    fi
}

# --------------------------
# FRP文件处理
# --------------------------
prepare_install() {
    cd "${INSTALL_DIR}" || exit 1
    
    # 检查现有文件
    if [ -f "frp_${FRP_VERSION}_linux_amd64.tar.gz" ]; then
        echo -e "${YELLOW}[!] 检测到已下载文件，跳过下载...${RESET}"
    else
        echo -e "${YELLOW}[+] 正在下载FRP v${FRP_VERSION}...${RESET}"
        if ! wget -q "${DOWNLOAD_URL}"; then
            echo -e "${RED}错误：文件下载失败，请检查：${RESET}"
            echo "1. 网络连接状态"
            echo "2. GitHub访问状态"
            exit 1
        fi
    fi
    
    # 解压文件
    if ! tar -zxvf "frp_${FRP_VERSION}_linux_amd64.tar.gz" > /dev/null 2>&1; then
        echo -e "${RED}错误：文件解压失败${RESET}"
        exit 1
    fi
}

# --------------------------
# 服务端安装
# --------------------------
install_frps() {
    echo -e "${BLUE}==================== 服务端配置 ====================${RESET}"
    
    # 交互式配置
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

    # 生成TOML配置
    cat > "${CONFIG_DIR}/frps.toml" << EOF
bindPort = ${BIND_PORT}
auth.token = "${TOKEN}"
vhostHTTPPort = ${HTTP_PORT}
webServer.addr = "0.0.0.0"
webServer.port = ${WEB_PORT}
webServer.user = "admin"
webServer.password = "${PASSWORD}"
EOF

    # 创建systemd服务
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

    # 验证安装
    if systemctl is-active --quiet frps; then
        echo -e "\n${GREEN}[√] FRP服务端安装成功！${RESET}"
        echo -e "----------------------------------------------"
        echo -e "${YELLOW}[!] 重要提示：${RESET}"
        echo -e "1. 请确保以下端口已在防火墙放行："
        echo -e "   - 服务端口：${BIND_PORT}/TCP"
        echo -e "   - HTTP代理：${HTTP_PORT}/TCP"
        echo -e "   - 管理端口：${WEB_PORT}/TCP"
        echo -e "2. 管理面板地址：http://服务器IP:${WEB_PORT}"
        echo -e "   登录账号：admin  密码：${PASSWORD}"
    else
        echo -e "${RED}[×] 服务启动失败，请检查：${RESET}"
        echo "1. 端口冲突情况"
        echo "2. 防火墙设置"
        echo "3. 查看日志：journalctl -u frps"
        exit 1
    fi
}

# --------------------------
# 客户端安装（已修复默认值问题）
# --------------------------
install_frpc() {
    echo -e "${BLUE}==================== 客户端配置 ====================${RESET}"
    
    # 强制验证必要参数
    while true; do
        read -e -p "服务器IP地址: " SERVER_IP
        if [[ -n "${SERVER_IP}" ]]; then
            break
        else
            echo -e "${RED}错误：服务器IP地址不能为空！${RESET}"
        fi
    done

    while true; do
        read -e -p "认证token (与服务端一致): " TOKEN
        if [[ -n "${TOKEN}" ]]; then
            break
        else
            echo -e "${RED}错误：认证token不能为空！${RESET}"
        fi
    done

    # 带默认值的端口设置
    read -e -p "服务端口 (默认7000): " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}

    # 生成客户端配置
    cat > "${CONFIG_DIR}/frpc.toml" << EOF
serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${TOKEN}"
EOF

    # 创建systemd服务
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
        echo -e "\n${GREEN}[√] FRP客户端安装成功！${RESET}"
        echo -e "----------------------------------------------"
        echo -e "${YELLOW}[!] 下一步操作建议：${RESET}"
        echo -e "1. 使用菜单选项3添加端口映射"
        echo -e "2. 在服务端开放对应远程端口"
    else
        echo -e "${RED}[×] 客户端启动失败，请检查：${RESET}"
        echo "1. 服务器IP和端口是否正确"
        echo "2. token是否与服务端一致"
        echo "3. 查看日志：journalctl -u frpc"
        exit 1
    fi
}

# --------------------------
# 端口映射管理（已修复显示问题）
# --------------------------
manage_proxies() {
    while true; do
        clear
        echo -e "${BLUE}=================== 端口映射管理 ==================${RESET}"
        echo " 1) 查看当前映射"
        echo " 2) 添加新映射"
        echo " 3) 删除现有映射"
        echo " 4) 返回主菜单"
        read -e -p "请选择操作 [1-4] (默认1): " PROXY_ACTION
        PROXY_ACTION=${PROXY_ACTION:-1}

        case $PROXY_ACTION in
            1) show_current_proxies ;;
            2) add_proxy_mapping ;;
            3) delete_proxy_mapping ;;
            4) return 0 ;;
            *) echo -e "${RED}无效选择，请重新输入${RESET}"; sleep 1 ;;
        esac
    done
}

# --------------------------
# 显示当前映射（修复TOML解析）
# --------------------------
show_current_proxies() {
    clear
    echo -e "${BLUE}=================== 当前端口映射 ==================${RESET}"
    
    if [ ! -f "${CONFIG_DIR}/frpc.toml" ]; then
        echo -e "${YELLOW}[!] 未找到客户端配置文件${RESET}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 使用AWK解析TOML格式
    awk '
    BEGIN { 
        print "编号  名称                协议    本地端口       => 远程端口"
        print "----------------------------------------------------"
    }
    /\[\[proxies\]\]/ {
        counter++
        getline
        split($0, name, "\"")
        getline
        split($0, type, "\"")
        getline
        split($0, local, "=")
        getline
        split($0, remote, "=")
        
        # 清理数据
        gsub(/ /, "", local[2])
        gsub(/ /, "", remote[2])
        
        printf "%-4s %-20s %-8s %-15s => %-15s\n", 
            counter, 
            name[2], 
            type[2], 
            local[2], 
            remote[2]
    }' "${CONFIG_DIR}/frpc.toml"

    read -n 1 -s -r -p "按任意键返回..."
}

# --------------------------
# 添加端口映射（兼容TOML）
# --------------------------
add_proxy_mapping() {
    echo -e "${BLUE}=================== 添加端口映射 ==================${RESET}"
    
    # 输入验证循环
    while true; do
        read -e -p "请输入映射名称 (示例: web): " proxy_name
        if [[ -n "$proxy_name" ]]; then
            break
        else
            echo -e "${RED}错误：映射名称不能为空！${RESET}"
        fi
    done

    read -e -p "选择协议类型 [tcp/udp] (默认tcp): " proxy_type
    proxy_type=${proxy_type:-tcp}

    # 端口输入验证
    while true; do
        read -e -p "请输入本地端口: " local_port
        if [[ "$local_port" =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "${RED}错误：本地端口必须为数字！${RESET}"
        fi
    done

    while true; do
        read -e -p "请输入远程端口: " remote_port
        if [[ "$remote_port" =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "${RED}错误：远程端口必须为数字！${RESET}"
        fi
    done

    # 追加TOML格式配置
    cat >> "${CONFIG_DIR}/frpc.toml" << EOF

[[proxies]]
name = "${proxy_name}"
type = "${proxy_type}"
localIP = "127.0.0.1"
localPort = ${local_port}
remotePort = ${remote_port}
EOF

    # 重启服务应用配置
    if systemctl restart frpc; then
        echo -e "${GREEN}[√] 成功添加映射：${RESET}"
        echo -e "名称: ${proxy_name}"
        echo -e "协议: ${proxy_type}"
        echo -e "本地端口: ${local_port} => 远程端口: ${remote_port}"
    else
        echo -e "${RED}[×] 配置添加成功，但服务重启失败${RESET}"
        echo -e "请手动执行：systemctl restart frpc"
    fi
    sleep 2
}

# --------------------------
# 删除端口映射（增强版）
# --------------------------
delete_proxy_mapping() {
    clear
    echo -e "${BLUE}=================== 删除端口映射 ==================${RESET}"
    
    if [ ! -f "${CONFIG_DIR}/frpc.toml" ]; then
        echo -e "${YELLOW}[!] 未找到客户端配置文件${RESET}"
        sleep 1
        return
    fi

    # 生成临时配置文件
    tmp_file=$(mktemp)
    cp "${CONFIG_DIR}/frpc.toml" "$tmp_file"

    # 显示现有映射
    echo -e "${GREEN}当前配置的端口映射：${RESET}"
    awk '
    /\[\[proxies\]\]/ {
        counter++
        getline
        name=$0
        getline
        type=$0
        getline
        localPort=$0
        getline
        remotePort=$0
        
        gsub(/^[ \t]+|[ \t]+$/, "", name)
        gsub(/^[ \t]+|[ \t]+$/, "", type)
        gsub(/^[ \t]+|[ \t]+$/, "", localPort)
        gsub(/^[ \t]+|[ \t]+$/, "", remotePort)
        
        printf "%-4s %-20s %-8s %-15s => %-15s\n", 
            counter, 
            gensub(/.*"(.+)".*/, "\\1", "g", name),
            gensub(/.*"(.+)".*/, "\\1", "g", type),
            gensub(/.*= *(.+)/, "\\1", "g", localPort),
            gensub(/.*= *(.+)/, "\\1", "g", remotePort)
    }' "$tmp_file"

    # 获取要删除的序号
    read -e -p "请输入要删除的映射序号 (0取消): " del_num
    if [[ "$del_num" -eq 0 ]]; then return; fi

    # 计算实际行号
    start_line=$(awk '/\[\[proxies\]\]/{print NR}' "$tmp_file" | sed -n "${del_num}p")
    if [ -z "$start_line" ]; then
        echo -e "${RED}错误：无效的序号${RESET}"
        sleep 1
        return
    fi

    # 删除对应配置块
    sed -i "$((start_line)),$((start_line+4))d" "$tmp_file"

    # 应用更改
    mv "$tmp_file" "${CONFIG_DIR}/frpc.toml"
    systemctl restart frpc
    
    echo -e "${GREEN}[√] 成功删除第${del_num}个映射配置${RESET}"
    sleep 1
}

# --------------------------
# 服务状态查看
# --------------------------
show_service_status() {
    clear
    echo -e "${BLUE}=================== 服务状态 ==================${RESET}"
    
    # 服务端状态
    echo -e "${GREEN}服务端状态：${RESET}"
    if systemctl is-active frps &> /dev/null; then
        systemctl status frps -l --no-pager
    else
        echo -e "${YELLOW}● frps未运行${RESET}"
    fi
    
    # 客户端状态
    echo -e "\n${GREEN}客户端状态：${RESET}"
    if systemctl is-active frpc &> /dev/null; then
        systemctl status frpc -l --no-pager
    else
        echo -e "${YELLOW}● frpc未运行${RESET}"
    fi
    
    read -n 1 -s -r -p "按任意键返回..."
}

# --------------------------
# 完全卸载
# --------------------------
uninstall_frp() {
    echo -e "${BLUE}=================== 卸载FRP ==================${RESET}"
    
    # 停止服务
    systemctl stop frps frpc 2>/dev/null
    systemctl disable frps frpc 2>/dev/null
    
    # 删除文件
    rm -rf "${INSTALL_DIR}"
    rm -f "${SERVICE_DIR}/frps.service" "${SERVICE_DIR}/frpc.service"
    
    # 清理配置
    firewall-cmd --remove-port={7000,7500,28080}/tcp --permanent 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    
    echo -e "${GREEN}[√] FRP已完全卸载${RESET}"
    sleep 1
}

# --------------------------
# 主程序流程
# --------------------------
main() {
    check_root
    init_directories
    while true; do
        show_main_menu
        case $MAIN_MODE in
            1) # 服务端安装
                install_dependencies
                prepare_install
                install_frps
                read -n 1 -s -r -p "操作完成，按任意键返回主菜单..."
                ;;
            2) # 客户端安装
                install_dependencies
                prepare_install
                install_frpc 
                read -n 1 -s -r -p "操作完成，按任意键返回主菜单..."
                ;;
            3) manage_proxies ;;    # 端口管理
            4) show_service_status;; # 状态查看
            5) uninstall_frp ;;     # 卸载
            6) # 退出
                echo -e "\n${YELLOW}[!] 感谢使用，再见！${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}[×] 无效的选择，请重新输入${RESET}"
                sleep 1
                ;;
        esac
    done
}

# 启动主程序
main
