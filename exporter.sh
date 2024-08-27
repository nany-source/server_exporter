#!/bin/bash

# 常量
SERVERNAME=""
ENDPOINT=""
APP_TOKEN=""
APP_SECRET=""
CURL_MAX_TIMEOUT=6

# 数据变量
isFirstgather=true
cpu_usage=()
cpu_total=0
cpu_idle=0
mem_usage=()
mem_total=0
disk_used=0
disk_total=0

function get_memory() {
    # 从文件获取内存信息
    local result=$(awk '/MemTotal/ {total=$2} /MemFree/ {free=$2} END {used=total-free; usage=(used/total)*100; print total, usage}' /proc/meminfo)

    # 赋值给全局变量
    mem_total=$(echo $result | awk '{print $1}')
    mem_usage+=($(echo $result | awk '{print $2}'))

    # echo "mem_total: ${mem_total}, mem_usage: ${mem_usage[@]}"
}

function get_disk() {
    # 拿 /挂载点的磁盘信息(排除标题行且固定终端语言)
    local result=$(LANG=C df / | awk 'NR>1 {print $2, $3}')

    # 赋值给全局变量
    disk_total=$(echo $result | awk '{print $1}')
    disk_used=$(echo $result | awk '{print $2}')

    # echo "disk_total: ${disk_total}, disk_used: ${disk_used}"
}

function get_cpu() {
    local result=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $5}' /proc/stat)
    local total=$(echo $result | awk '{print $1}')
    local idle=$(echo $result | awk '{print $2}')

    # 如果是首次则直接记录不进行比较运算
    if [ "$isFirstgather" = true ]; then
        cpu_total=$total
        cpu_idle=$idle
        isFirstgather=false
    else
        # 计算cpu使用率
        cpu_usage+=($(echo "scale=2; (($total-$cpu_total)-($idle-$cpu_idle))/($total-$cpu_total)*100" | bc))

        # 更新全局变量
        cpu_total=$total
        cpu_idle=$idle
    fi

    # echo "total: ${cpu_total}, idle: ${cpu_idle}, cpu_usage: ${cpu_usage[@]}"
}

function post_data() {
    # 获取一次磁盘信息
    get_disk

    # 获取数组长度
    local cpuCount=${#cpu_usage[@]}
    local memCount=${#mem_usage[@]}

    # 如果cpu的数组为空则不处理
    if [ $cpuCount -eq 0 ]; then
        return
    fi

    # 计算cpu的平均使用率
    local cpuSum=0
    for usage in ${cpu_usage[@]}; do
        cpuSum=$(echo $cpuSum+$usage | bc)
    done
    local cpuAvg=$(echo "scale=2; ($cpuSum/$cpuCount)*100" | bc)

    # 计算内存的平均使用率
    local memSum=0
    for usage in ${mem_usage[@]}; do
        memSum=$(echo $memSum+$usage | bc)
    done
    local memAvg=$(echo "scale=2; $memSum/$memCount" | bc)

    # 清空数组
    cpu_usage=()
    mem_usage=()

    # 构造要发送的数据结构
    local json_data=$(cat <<EOF
{
    "server": "${SERVERNAME}",
    "cpu_c": ${cpuAvg},
    "cpu_m": 10000,
    "mem_c": ${memAvg},
    "mem_m": ${mem_total},
    "disk_c": ${disk_used},
    "disk_m": ${disk_total},
    "ts": $(date +%s)
}
EOF
    )

    # 发送数据
    local result=$(curl -sSL -X POST -H "Content-Type: application/json" -H "APP-KEY: ${APP_TOKEN}" -H "APP-SECRET: ${APP_SECRET}" -d "${json_data}" ${ENDPOINT} --max-time ${CURL_MAX_TIMEOUT})
    # 如果发送成功则判断是否带特定字符串
    if [ $? -eq 0 ]; then
        if ! [[ $result == *'{"code":0'* ]]; then
            echo "Error: Response code not 0!" 1>&2
        fi
    else
        echo "Error: Data sent failed!" 1>&2
    fi
}

####################################################### MAIN #######################################################

# 检查curl是否安装且可执行
if ! [ -x "$(command -v curl)" ]; then
    echo "Error: curl is not installed!" 1>&2
    exit 1
fi

# 检查是否安装bc数学运算库
if ! [ -x "$(command -v bc)" ]; then
    echo "Error: bc is not installed!" 1>&2
    exit 1
fi

# 接收传参
if [ $# -ge 4 ]; then
    SERVERNAME=$1
    ENDPOINT=$2
    APP_TOKEN=$3
    APP_SECRET=$4
    # 如果第五个传参存在则赋值到curl的最大超时时间
    if [ $5 ]; then
        # 如果非数值则报错
        if ! [[ $5 =~ ^[0-9]+$ ]]; then
            echo "Error: The fifth parameter must be a number!" 1>&2
            exit 1
        fi
        CURL_MAX_TIMEOUT=$5
    fi
else
    echo "Usage: $0 <servername> <endpoint> <app-token> <app-secret> <curl-max-timeout:default 6 sec>"
    echo "Example: $0 OssServer http://127.0.0.1:8000/api/p test secrets 6"
    exit 1
fi

echo "Server Exporter is running..."

# 获取一次数据的间隔
getData_interval=10

# 获取脚本启动时的时间戳
start_timestamp=$(date +%s)

# 计算下一个整分钟的时间戳
next_minute_timestamp=$(((start_timestamp/60+1)*60))

# 循环获取数据
while true; do
    # 获取cpu和内存信息
    get_cpu
    get_memory

    # 获取当前时间戳
    current_timestamp=$(date +%s)

    # 如果当前时间大于等于下一个整分钟的时间戳则发送数据
    if [ $current_timestamp -ge $next_minute_timestamp ]; then
        post_data
        # 获取下个整分钟的时间戳
        next_minute_timestamp=$(((current_timestamp/60+1)*60))
    fi

    # 等待到下一次执行
    sleep $getData_interval
done
