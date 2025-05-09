# frp
frp一键端
你可以将整个安装过程合并为一条命令，使用 && 连接多个步骤。这里是一键安装命令：

bash
sudo dnf install -y dos2unix && \
sudo curl -L "https://raw.githubusercontent.com/aakk007/frp/main/install_frps_frpc.sh" -o /usr/local/install_frps_frpc.sh && \
sudo dos2unix /usr/local/install_frps_frpc.sh && \
sudo chmod +x /usr/local/install_frps_frpc.sh && \
sudo /usr/local/install_frps_frpc.sh


使用说明：
复制命令：直接复制上述完整命令。

粘贴执行：在终端中粘贴并执行，脚本会自动完成所有步骤。

注意事项：
URL 修正：我调整了 GitHub 的下载链接，使用 raw.githubusercontent.com 确保直接下载脚本文件（原链接中的 blob 会导致下载 HTML 页面而非脚本）。

路径与文件名：确保脚本保存到 /usr/local/install_frps_frpc.sh，与你原路径一致。

依赖安装：sudo dnf install -y dos2unix 会自动安装格式转换工具。

如果遇到权限问题，也可以用更简洁的「管道流式执行」：
bash
sudo dnf install -y dos2unix && \
curl -sL https://raw.githubusercontent.com/aakk007/frp/main/install_frps_frpc.sh | dos2unix | sudo bash
优点：无需保存脚本文件，直接通过管道执行。

缺点：脚本不会保留在本地，适合一次性安装。
