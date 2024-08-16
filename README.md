# Server Exporter

[EN](https://github.com/nany-source/server_exporter/blob/main/README.md) | [中文](https://github.com/nany-source/server_exporter/blob/main/README_CN.md)

### It's a simple golang that exports server metrics (CPU used / Memory used / Mount"/" disk used).

### ⚠️Notes⚠️
- This exporter use system command and awk command to get metrics.
    - ⚠️**Please make sure that the terminal is in English language and not in other languages.**
- This exporter only works on Linux systems. 
    - Tested on Ubuntu 20.04 or higher.
    - Other distributions may work but not tested.
- This exporter is not openmetrics compliant. It's a simple exporter that exports metrics in a simple format.
- This exporter is automatically shutdown at 00:00 erevyday.
    - This is used to prevent memory leaks that may occur over time.
    - Please register the exporter as a (Restart=always) service or used supervisor to run.
- The exporter sends data to the endpoint every minute.

## Table of Contents
- [How to use](#how-to-use)
    - [With bash script](#with-bash-script)
    - [With Manual deployment](#with-manual-deployment)
- [Configuration file](#configuration-file)
- [Metrics Post Data](#metrics-post-data)

## How to use
### With bash script
- ### Download the bash script
```bash
curl -Lo server_exporter.sh https://raw.githubusercontent.com/nany-source/server_exporter/main/server_exporter.sh && chmod +x server_exporter.sh
```
- ### Install
```bash
./server_exporter.sh install
```
- The script will do the following:
    - Download exporter last release binary / config.
    - Install the exporter as a service. The exporter will be started automatically when the system is started.
    - During the installation, the script will use default editor ask you to edit the configuration file.

- ### Support other usage
- <details>
    <summary>Click to expand!</summary>
    
    - ### Update
    ```bash
    ./server_exporter.sh update
    ```
    - The script will do the following:
        - Check the latest release of the exporter.
        - If the latest release is different from the current release, the script will download the latest release and update the service.

    - ### Uninstall
    ```bash
    ./server_exporter.sh uninstall
    ```
    - The script will do the following:
        - Stop the exporter service.
        - Remove the exporter service.
        - Remove the exporter binary.
        - Remove the exporter configuration file.
</details>

### With Manual deployment
- e.g 
    - Export binary path:  **/usr/local/bin/server_exporter**
    - Configuration file path:  **/etc/server_exporter/config.json**

- ### Download the exporter binary and configuration file
```bash
# Download the exporter binary
curl -Lo /usr/local/bin/server_exporter https://github.com/nany-source/server_exporter/releases/download/Github_Actions_Build/server_exporter && chmod +x /usr/local/bin/server_exporter

# Checksum verification
curl -Lo /tmp/server_exporter.sha256 https://github.com/nany-source/server_exporter/releases/download/Github_Actions_Build/server_exporter.sha256
echo "$(sha256sum /usr/local/bin/server_exporter | awk '{print $1}')" | diff - /tmp/server_exporter.sha256
# If the output is empty, the checksum is correct. Otherwise, exporter binary may be tampered with or broken.

# Download the exporter configuration file
curl -Lo /etc/server_exporter/config.json https://raw.githubusercontent.com/nany-source/server_exporter/main/server_exporter.json

# Edit the configuration file (edit endpoint, app_token, app_secret etc ...)
vi /etc/server_exporter/config.json
```
- ### Create service (systemd) or use supervisor to run
    - If you want to create a service(systemd), you can use the following example.
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
    - Create a service file in **/etc/systemd/system/server_exporter.service**. (working in Ubuntu 20.04 or higher)
        - ⚠️This path may vary depending on the distribution.
        - ⚠️Please check the path of the service file before creating it.
    - Please replace `${USER_SETTING}` with your settings.
        - e.g
            ```bash
            User=nobody
            Group=nogroup
            ```
        - ⚠️**DON'T USE ROOT USER TO RUN THE EXPORTER.**
        - ⚠️**Please use nologin shell user to run the exporter(or limited permission account)**
- ### Enable and start the service
    ```bash
    systemctl daemon-reload
    systemctl enable server_exporter
    systemctl start server_exporter
    ```

## Configuration file
- The configuration file is a JSON format file.
- The default configuration file is as follows.
    ```json
    {
        "server_name": "test",
        "endpoint": "http://10.0.0.57:8000/api/test",
        "app_token": "task",
        "app_secret": "task",
        "log_level": "WARN"
    }
    ```
- The configuration file has the following fields.
    - `server_name`: The name of the server.
    - `endpoint`:   The endpoint to send the metrics. (e.g `http://ip:port/path`)
    - `app_token`:  token for the application.
    - `app_secret`: secret key for the application.
    - `log_level`: 
        - Minimum log level to output to the console.
        - The log level is one of the following.
            - `DEBUG`
            - `INFO`
            - `WARN`
            - `ERROR`
- ⚠️Please make sure that the path to save the config file is readable by the user running the exporter.

## Metrics Post Data
- The metrics are sent to the endpoint in the following format.
    - Method: **POST**
    - Header
        ```json
        {
            "APP-Key": your_configuration_file_token,
            "APP-Token": your_configuration_file_secret,
        }
        ```
    - Post body
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
    - The metrics are sent in the following format.
        - Header fields (Used by your application to verify the source of the metrics)
            - `APP-Key`: app token
            - `APP-Token`: app secret
        - Post body fields
            - `cpu_c`: Occupancy rate for the last 1 minute of CPU.
            - `cpu_m`: Maximum occupancy rate of CPU.
            - `disk_c`: Used space of the "/" mount point. (KB)
            - `disk_m`: Total space of the "/" mount point. (KB)
            - `mem_c`: The amount of memory used. (KB)
            - `mem_m`: Total memory. (KB)
            - `server`: The name of the server.
            - `ts`: The timestamp when the metrics were sent.

    - **Curl example**
        ```bash
        curl -X POST http://your-api-endpoint/path \
            -H "Content-Type: application/json" \
            -H "APP-Key: your_configuration_file_token" \
            -H "APP-Token: your_configuration_file_secret" \
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