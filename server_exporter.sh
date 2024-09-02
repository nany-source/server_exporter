#!/bin/bash

# 下载路径
BINARY_FILE_DOWNLOAD_URL="https://github.com/nany-source/server_exporter/releases/download/Github_Actions_Build/server_exporter"
BASH_EXPORTER_FILE_DOWNLOAD_URL="https://raw.githubusercontent.com/nany-source/server_exporter/main/exporter.sh"
CHECKSUM_FILE_DOWNLOAD_URL="https://github.com/nany-source/server_exporter/releases/download/Github_Actions_Build/server_exporter.sha256"
CONFIG_FILE_DOWNLOAD_URL="https://raw.githubusercontent.com/nany-source/server_exporter/main/server_exporter.json"
BASH_SCRIPT_DOWNLOAD_URL="https://raw.githubusercontent.com/nany-source/server_exporter/main/server_exporter.sh"
# 名称
SERVICE_NAME="server-exporter"
BINARY_FILE_NAME="server_exporter"
BASH_EXPORTER_FILE_NAME="exporter.sh"
# 放置路径
SERVICE_FILE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_CONF_PATH="/etc/server_exporter/${SERVICE_NAME}.config"
BINARY_FILE_PATH="/usr/local/bin/${BINARY_FILE_NAME}"
BASH_EXPORTER_FILE_PATH="/usr/local/bin/${BASH_EXPORTER_FILE_NAME}"

# 检查是否为root用户运行 (root用户才有权限操作服务)
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script!" 1>&2
    exit 1
fi

# 检查curl是否安装且可执行
if ! [ -x "$(command -v curl)" ]; then
    echo "Error: curl is not installed!" 1>&2
    exit 1
fi

# 根据传参执行对应操作
case "$1" in
    install)
        # 检查是否已经安装
        server_status=$(systemctl list-unit-files | grep ${SERVICE_NAME} | awk '{print $2}')
        if [ -n "${server_status}" ]; then
            echo "Error: The service is already installed!" 1>&2
            exit 1
        fi

        # 从github下载最新的二进制文件和配置文件
        echo "Download binary file and config file from github..."
        # 检查目录是否存在,不存在则创建
        if [ ! -d "/etc/server_exporter" ]; then
            mkdir -p /etc/server_exporter
        fi
        # 下载二进制文件
        curl -sSL ${BINARY_FILE_DOWNLOAD_URL} -o ${BINARY_FILE_PATH}
        # 获取下载的文件的checksum
        online_checksum=$(curl -sSL ${CHECKSUM_FILE_DOWNLOAD_URL})
        current_checksum=$(sha256sum ${BINARY_FILE_PATH} | awk '{print $1}')
        # 比较checksum
        if [ "${current_checksum}" != "${online_checksum}" ]; then
            echo "Error: Checksum verification failed!" 1>&2
            exit 1
        fi
        # 下载配置文件
        curl -sSL ${CONFIG_FILE_DOWNLOAD_URL} -o ${SERVICE_CONF_PATH}

        # 二进制文件设置可执行权限
        echo "Setting permissions..."
        chmod 755 ${BINARY_FILE_PATH}
        # 配置文件设置权限
        chmod 644 ${SERVICE_CONF_PATH}

        # 获取systemd版本(根据版本动态设置安全账户)
        systemdVersion=$(systemctl --version | head -n 1 | awk '{print $2}')
        # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#DynamicUser=
        # 低于232版本不支持DynamicUser, 需要换成debian自带的无权限账户nobody
        if [ ${systemdVersion} -lt 232 ]; then
            echo "Systemd version is lower than 232, use nobody user."
            USER_SETTING="User=nobody"$'\n'"Group=nogroup"
        else
            echo "Systemd version is greater than 232, use DynamicUser."
            # 232版本以上支持DynamicUser, 使用动态用户(防止nobody的安全警告)
            USER_SETTING="DynamicUser=true"
        fi

        # 创建服务
        echo "Create service..."
        cat > ${SERVICE_FILE_PATH} <<EOF
[Unit]
Description=Server Cpu/Mem/Disk Info exporter and upload
After=network.target

[Service]
Type=simple
ExecStart=${BINARY_FILE_PATH} -config=${SERVICE_CONF_PATH}
Restart=always
RestartSec=3
${USER_SETTING}

[Install]
WantedBy=multi-user.target
EOF

        # 重载配置并启动服务
        echo "Reload systemd..."
        systemctl daemon-reload

        echo "Enable service..."
        systemctl enable ${SERVICE_NAME}

        echo "Install success!"

        # 使用vi打开配置文件
        vi ${SERVICE_CONF_PATH}

        # 提示
        echo "Config file path: ${SERVICE_CONF_PATH}"
        echo "Run 'systemctl start ${SERVICE_NAME}' to start the service."
        ;;
    install_bash)
        # 检查是否已经安装
        server_status=$(systemctl list-unit-files | grep ${SERVICE_NAME} | awk '{print $2}')
        if [ -n "${server_status}" ]; then
            echo "Error: The service is already installed!" 1>&2
            exit 1
        fi

        # 从github下载最新的脚本文件
        echo "Download bash script file from github..."
        curl -sSL ${BASH_EXPORTER_FILE_DOWNLOAD_URL} -o ${BASH_EXPORTER_FILE_PATH}

        # 设置可执行权限
        echo "Setting permissions..."
        chmod 755 ${BASH_EXPORTER_FILE_PATH}

        # 获取systemd版本(根据版本动态设置安全账户)
        systemdVersion=$(systemctl --version | head -n 1 | awk '{print $2}')
        # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#DynamicUser=
        # 低于232版本不支持DynamicUser, 需要换成debian自带的无权限账户nobody
        if [ ${systemdVersion} -lt 232 ]; then
            echo "Systemd version is lower than 232, use nobody user."
            USER_SETTING="User=nobody"$'\n'"Group=nogroup"
        else
            echo "Systemd version is greater than 232, use DynamicUser."
            # 232版本以上支持DynamicUser, 使用动态用户(防止nobody的安全警告)
            USER_SETTING="DynamicUser=true"
        fi

        # 创建服务
        echo "Create service..."
        cat > ${SERVICE_FILE_PATH} <<EOF
[Unit]
Description=Server Cpu/Mem/Disk Info exporter and upload
After=network.target

[Service]
Type=simple
ExecStart=${BASH_EXPORTER_FILE_PATH} servername endpoint app-token app-secret
Restart=always
RestartSec=3
${USER_SETTING}

[Install]
WantedBy=multi-user.target
EOF

        # 使用vi打开服务文件
        vi ${SERVICE_FILE_PATH}

        # 重载配置并启动服务
        echo "Reload systemd..."
        systemctl daemon-reload

        echo "Enable service..."
        systemctl enable ${SERVICE_NAME}

        echo "Install success!"
        echo "Run 'systemctl start ${SERVICE_NAME}' to start the service."
        ;;
    uninstall)
        # 检查是否已经安装
        server_status=$(systemctl list-unit-files | grep ${SERVICE_NAME} | awk '{print $2}')
        if [ -z "${server_status}" ]; then
            echo "Error: The service is not installed!" 1>&2
            exit 1
        fi

        # 停止并禁用服务
        echo "Stopping and disabling service..."
        systemctl stop ${SERVICE_NAME}
        systemctl disable ${SERVICE_NAME}

        # 删除服务文件
        echo "Removing service file..."
        rm -f ${SERVICE_FILE_PATH}
        systemctl daemon-reload

        # 删除二进制文件和配置文件
        echo "Removing binary file and config file..."
        rm -f ${BINARY_FILE_PATH}
        rm -f ${BASH_EXPORTER_FILE_PATH}
        # rm -f ${SERVICE_CONF_PATH}

        echo "Uninstall service success!"
        ;;
    update)
        # 检查文件是否存在,不存在则返回错误
        if [ ! -f ${BINARY_FILE_PATH} ]; then
            echo "Error: Binary file not found!" 1>&2
            exit 1
        fi

        # 获取当前二进制文件的checksum
        current_checksum=$(sha256sum ${BINARY_FILE_PATH} | awk '{print $1}')
        if [ -z "${current_checksum}" ]; then
            echo "Error: Get current checksum failed!" 1>&2
            exit 1
        fi

        # 从github获取最新的checksum信息
        echo "Check binary file update..."
        online_checksum=$(curl -sSL ${CHECKSUM_FILE_DOWNLOAD_URL})
        if [ -z "${online_checksum}" ]; then
            echo "Error: Get online checksum failed!" 1>&2
            exit 1
        fi

        # 比较checksum,如果一致则不需要更新
        if [ "${current_checksum}" == "${online_checksum}" ]; then
            echo "The binary file is up to date, no need to update!"
            exit 0
        fi

        # 下载最新的二进制文件
        echo "Has new version! Download latest binary file from github..."
        # 下载到临时位置
        temp_binary_file_path="/tmp/github_actions_build_${BINARY_FILE_NAME}"
        curl -sSL ${BINARY_FILE_DOWNLOAD_URL} -o ${temp_binary_file_path}

        # 获取下载的文件的checksum与在线的checksum比较
        temp_checksum=$(sha256sum ${temp_binary_file_path} | awk '{print $1}')
        # 为空则为下载失败
        if [ -z "${temp_checksum}" ]; then
            echo "Error: Get temp checksum failed! Download failed!" 1>&2
            exit 1
        fi
        # 不匹配为下载不完整
        if [ "${temp_checksum}" != "${online_checksum}" ]; then
            echo "Error: Checksum verification failed! Download failed!" 1>&2
            exit 1
        fi

        # 校验通过,替换二进制文件
        echo "Replace binary file..."
        mv -f ${temp_binary_file_path} ${BINARY_FILE_PATH}
        # 设置权限
        chmod 755 ${BINARY_FILE_PATH}

        # 获取服务状态
        server_status=$(systemctl list-unit-files | grep ${SERVICE_NAME} | awk '{print $2}')
        # 如果服务未安装,则不重启服务
        if [ -z "${server_status}" ]; then
            echo "Warning: Service is not install! Cancel restart service!"
        # 服务已安装, 但未启用也不重启服务
        elif [ ${server_status} == "disabled" ]; then
            echo "Warning: Service is not enabled! Cancel restart service!"
        else
            # 已启用, 则重启服务
            echo "Restart service..."
            systemctl restart ${SERVICE_NAME}
        fi

        echo "Update success!"
        ;;
    *)
        # 默认提示
        echo "Usage: $0 [install|install_bash|uninstall|update]"
        echo "- install: Install the exporter with binary version and create a service."
        echo "- install_bash: Install the exporter with bash script version and create a service."
        echo "- uninstall: Uninstall the exporter and remove the service."
        echo "- update: Update the exporter with binary version to the latest version."
        exit 0
        ;;
esac
