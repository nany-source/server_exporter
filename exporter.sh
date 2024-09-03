#!/bin/bash

# 常量
SERVERNAME=""
ENDPOINT=""
APP_KEY=""
APP_TOKEN=""
CURL_MAX_TIMEOUT=6

# 数据变量
cpu_total=(0, 0)
cpu_total_now=0
# 184467440772488221456
cpu_idle=(0, 0)
cpu_idle_now=0
mem_used=(0, 0)
mem_used_now=0
mem_total=0
disk_used=0
disk_total=0

# 输出debug信息
debug=false

function get_memory() {
    # 从文件获取内存信息(不可使用/proc/meminfo, 因为free需要额外计算)
    # local result=$(awk '/MemTotal/ {total=$2} /MemFree/ {free=$2} END {used=total-free; print total, used}' /proc/meminfo)
    local result=$(LANG=C free | awk 'NR==2 {printf "%.0f %.0f", $2, $3}')

    # 如果内存信息获取失败则不处理
    if [ -z "$result" ]; then
        return
    fi

    # 获取数据
    local used=$(echo $result | awk '{print $2}')
    # total赋值给全局变量
    mem_total=$(echo $result | awk '{print $1}')

    # 如果第一个传参是true则记录在数组的第一个位置
    if [ "$1" = true ]; then
        mem_used[0]=$used
    else
        mem_used[1]=$used
        mem_used_now=$used
    fi

    if [ "$debug" = true ]; then
        echo "mem_total: ${mem_total}, mem_used: ${mem_used[@]}"
    fi
}

function get_disk() {
    # 拿 /挂载点的磁盘信息(排除标题行且固定终端语言)
    local result=$(LANG=C df / | awk 'NR>1 {printf "%.0f %.0f", $2, $3}')

    # 赋值给全局变量
    disk_total=$(echo $result | awk '{print $1}')
    disk_used=$(echo $result | awk '{print $2}')

    if [ "$debug" = true ]; then
        echo "disk_total: ${disk_total}, disk_used: ${disk_used}"
    fi
}

function get_cpu() {
    # 获取占用的total时间
    local result=$(awk '/^cpu / {printf "%.0f %.0f", ($2+$3+$4+$5+$6+$7+$8+$9)/256, $5/256}' /proc/stat)

    # 如果获取失败则不处理
    if [ -z "$result" ]; then
        return
    fi

    # 提取数据
    local total=$(echo $result | awk '{print $1}')
    local idle=$(echo $result | awk '{print $2}')

    # 如果第一个传参是true则记录在数组的第一个位置
    if [ "$1" = true ]; then
        cpu_total[0]=$total
        cpu_idle[0]=$idle
    else
        # 否则更新数组的第二个位置
        cpu_total[1]=$total
        cpu_total_now=$total
        cpu_idle[1]=$idle
        cpu_idle_now=$idle
    fi

    if [ "$debug" = true ]; then
        echo "total: ${cpu_total[@]}, idle: ${cpu_idle[@]}"
    fi
}

function post_data() {
    # 获取cpu和内存信息
    get_cpu
    get_memory
    # 获取一次磁盘信息
    get_disk

    # 如果cpu/mem的数据有一个为0都不上传数据
    if [ ${cpu_total[0]} -eq 0 ] || [ ${cpu_total[1]} -eq 0 ] || [ ${cpu_idle[0]} -eq 0 ] || [ ${cpu_idle[1]} -eq 0 ]; then
        return
    fi

    # 计算cpu的平均使用率
    local cpuAvg=$(echo "scale=2; (1-((${cpu_idle[1]}-${cpu_idle[0]})/(${cpu_total[1]}-${cpu_total[0]})))*10000" | bc)
    # 把now值写入对应数组的第一个位置
    cpu_total[0]=$cpu_total_now
    cpu_idle[0]=$cpu_idle_now

    # 计算内存的平均使用率
    local memSum=0
    local memAvg=0
    for usage in ${mem_used[@]}; do
        memSum=$(echo $memSum+$usage | bc)
    done
    # 如果内存数组大于0则取平均值，否则为0
    memAvg=$(echo "scale=2; $memSum/2" | bc)
    mem_used[0]=$mem_used_now

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
    local result=$(curl -sSL -X POST -H "Content-Type: application/json" -H "APP-KEY: ${APP_KEY}" -H "APP-TOKEN: ${APP_TOKEN}" -d "${json_data}" ${ENDPOINT} --max-time ${CURL_MAX_TIMEOUT})
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
    APP_KEY=$3
    APP_TOKEN=$4
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

# 先获取一次cpu和memory
get_cpu true
get_memory true

# 循环获取数据
while true; do
    # 获取当前时间戳
    current_timestamp=$(date +%s)

    # 如果当前时间大于等于下一个整分钟的时间戳则发送数据
    if [ $current_timestamp -ge $next_minute_timestamp ]; then
        post_data
        # 获取下个整分钟的时间戳
        next_minute_timestamp=$(((current_timestamp/60+1)*60))
    fi

    # 获取到下一分钟所需的秒数
    sleep_seconds=$((next_minute_timestamp-current_timestamp))

    # 等待到下一次执行
    if [ "$debug" = true ]; then
        echo "Sleep ${sleep_seconds} seconds..."
    fi

    sleep $sleep_seconds
done
