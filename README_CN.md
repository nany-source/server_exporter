# Server Exporter

[EN](https://github.com/nany-source/server_exporter/blob/main/README.md) | [中文](https://github.com/nany-source/server_exporter/blob/main/README_CN.md)

### 这是一个用golang编写的简单服务器指标导出器（CPU使用率/内存使用率/"/"挂载点的磁盘使用率）。

### ⚠️提示⚠️
- 导出器使用了系统命令获取和awk指令裁切数据.
    - ⚠️**请务必确保系统的终端的语言为英文. 因为某些系统指令会根据终端语言进行变化, 会导致切割数据错误**.
- 导出器只支持Linux系统. 
    - 程序在Ubuntu 20.04 或更高版本的系统中通过测试.
    - 其他发行版可能可以使用但未经过测试.
- 导出器导出的数据不符合OpenMetrics规范. 它是一个简单的导出器，以简单的格式导出指标.
- 导出器每天00:00自动关闭.
    - 这是为了防止长时间运行有可能的内存泄漏.
    - 请注册为(Restart=always)服务或使用supervisor运行导出器.
- 导出器会每分钟发送一次数据到接收地址.

## 目录
- [如何使用](#如何使用)
    - [使用bash脚本](#使用bash脚本)
    - [手动部署](#手动部署)
- [配置文件](#配置文件)
- [采集指标的POST数据](#采集指标的post数据)

## 如何使用
### 使用bash脚本
- ### 下载bash脚本
```bash
curl -Lo server_exporter.sh https://raw.githubusercontent.com/nany-source/server_exporter/main/server_exporter.sh && chmod +x server_exporter.sh
```
- ### 安装
```bash
./server_exporter.sh install
```
- 脚本会进行以下操作:
    - 下载最新版的导出器二进制文件/配置文件.
    - 将导出器安装为服务. 系统启动时导出器将自动启动.
    - 在安装过程中, 脚本会使用默认编辑器询问您编辑配置文件.

- ### 脚本支持的其他操作
- <details>
    <summary>点我展开啦!</summary>
    
    - ### 更新
    ```bash
    ./server_exporter.sh update
    ```
    - 脚本会进行以下操作:
        - 检查导出器的最新版本.
        - 如果最新版本与当前版本不同, 脚本将下载最新版本并重启服务.

    - ### 卸载
    ```bash
    ./server_exporter.sh uninstall
    ```
    - 脚本会进行以下操作:
        - 停止导出器服务.
        - 删除导出器服务.
        - 删除导出器二进制文件.
        - 删除导出器配置文件.
</details>

### 手动部署
- 例如 
    - 导出器二进制文件路径:  **/usr/local/bin/server_exporter**
    - 导出器配置文件路径:  **/etc/server_exporter/config.json**

- ### 下载导出器二进制文件和配置文件
```bash
# 下载导出器二进制文件
curl -Lo /usr/local/bin/server_exporter https://github.com/nany-source/server_exporter/releases/download/Github_Actions_Build/server_exporter && chmod +x /usr/local/bin/server_exporter

# 校验和验证
curl -Lo /tmp/server_exporter.sha256 https://github.com/nany-source/server_exporter/releases/download/Github_Actions_Build/server_exporter.sha256
echo "$(sha256sum /usr/local/bin/server_exporter | awk '{print $1}')" | diff - /tmp/server_exporter.sha256
# 如果输出为空则校验和正确. 否则, 导出器二进制文件可能被篡改或损坏.

# 下载导出器配置文件
curl -Lo /etc/server_exporter/config.json https://raw.githubusercontent.com/nany-source/server_exporter/main/server_exporter.json

# 编辑配置文件 (编辑endpoint, app_token, app_secret等 ...)
vi /etc/server_exporter/config.json
```
- ### 创建服务(systemd)或使用supervisor运行
    - 如果您想创建一个服务(systemd), 您可以使用以下示例.
    - 在 **/etc/systemd/system/server_exporter.service** 创建服务文件. (在 Ubuntu 20.04 或更高版本此路径可用)
        - ⚠️此路径会因为不同系统而有所不同.
        - ⚠️请在创建服务文件前检查服务文件的路径.
    - 请替换 `${USER_SETTING}` 为你的设定.
        - 例如
            ```bash
            User=user
            Group=group
            ```
        - ⚠️**不要使用ROOT账户运行导出器.**
        - ⚠️**请使用基于nologin shell的用户运行导出器(或有限权限的账户)**
        ```bash
        [Unit]
        Description=Server Cpu/Mem/Disk Info exporter and upload
        After=network.target

        [Service]
        Type=simple
        ExecStart=/usr/local/bin/server_exporter -config=/etc/server_exporter/config.json
        Restart=always
        RestartSec=3
        ${USER_SETTING}

        [Install]
        WantedBy=multi-user.target
        ```
- ### 启用并启动服务
    ```bash
    systemctl daemon-reload
    systemctl enable server_exporter
    systemctl start server_exporter
    ```

## 配置文件
- 此配置文件为JSON格式.
- 默认配置文件如下.
    ```json
    {
        "server_name": "test",
        "endpoint": "http://10.0.0.57:8000/api/test",
        "app_token": "task",
        "app_secret": "task",
        "log_level": "WARN"
    }
    ```
- 配置文件的字段解释
    - `server_name`: 服务器名称.
    - `endpoint`:   接收采集指标的地址.  (格式 `http://ip:port/path`)
    - `app_token`:  用于身份验证的应用程序的令牌.
    - `app_secret`: 用于身份验证的应用程序的密钥.
    - `log_level`: 
        - 控制输出到控制台的日志级别.
        - 日志级别有以下几种.
            - `DEBUG`
            - `INFO`
            - `WARN`
            - `ERROR`
- ⚠️请确保配置文件的路径正确并且导出器有权限读取配置文件.

## 采集指标的POST数据
- 指标以以下格式发送到接收地址.
    - 请求类型: **POST**
    - 请求头
        ```json
        {
            "APP-Key": 你在配置文件中设置的token,
            "APP-Token": 你在配置文件中设置的secret,
        }
        ```
    - 请求体
        ```json
        {
            "cpu_c":7.605416876844534,
            "cpu_m":10000,
            "disk_c":49899104,
            "disk_m":229585228,
            "mem_c":1995728.8,
            "mem_m":32745720,
            "server":"test",
            "ts":1723718855
        }
        ```
    - 请求体字段
        - 请求头字段
            - `APP-Key`: 令牌
            - `APP-Token`: 密钥
        - 请求体字段
            - `cpu_c`: 最近1分钟的cpu占用率
            - `cpu_m`: cpu的最大占用率
            - `disk_c`: "/"挂载点的已使用空间 (KB)
            - `disk_m`: "/"挂载点的总空间 (KB)
            - `mem_c`: 内存使用量. (KB)
            - `mem_m`: 内存总量. (KB)
            - `server`: 服务器名称.
            - `ts`: 发送时的时间戳.
    
    - **Curl 示例**
        ```bash
        curl -X POST http://your-api-endpoint/path \
            -H "Content-Type: application/json" \
            -H "APP-Key: 你在配置文件中设置的token," \
            -H "APP-Token: 你在配置文件中设置的secret" \
            -d '{
                "cpu_c": 7.605416876844534,
                "cpu_m": 10000,
                "disk_c": 49899104,
                "disk_m": 229585228,
                "mem_c": 1995728.8,
                "mem_m": 32745720,
                "server": "test",
                "ts": 1723718855
                }'
        ```