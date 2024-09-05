#!/bin/bash

# 常量
SERVERNAME=""
ENDPOINT=""
APP_KEY=""
APP_TOKEN=""
CURL_MAX_TIMEOUT=6
# 每分钟的数据采样数(最大60)
GETDATA_COUNT_MINUTE=10
CPU_MAX=10000

# 数据变量
cpu_usage=()
cpu_total=0
cpu_idle=0
mem_used=()
mem_total=0
disk_used=0
disk_total=0
is_first=true

# 输出debug信息
debug=false

function get_memory() {
    # 从文件获取内存信息(不可使用/proc/meminfo, 因为free需要额外计算)
    # 获取total和used的值
    local result=$(LANG=C free | awk 'NR==2 {printf "%.0f %.0f", $2, $3}')

    # 如果内存信息获取失败则不处理
    if [ -z "$result" ]; then
        return
    fi

    # 赋值给全局变量
    mem_total=$(echo $result | awk '{print $1}')
    mem_used+=($(echo $result | awk '{print $2}'))

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
    if [ "$is_first" = true ]; then
        cpu_total=$total
        cpu_idle=$idle
        is_first=false
    else
        # 计算出占用率
        cpu_usage+=($(echo "scale=2; (1-($idle-$cpu_idle)/($total-$cpu_total))*$CPU_MAX" | bc))
        # 把新数据记录下来
        cpu_total=$total
        cpu_idle=$idle
    fi

    if [ "$debug" = true ]; then
        echo "cpu_usage: ${cpu_usage[@]}"
    fi
}

function post_data() {
    # 获取一次磁盘信息
    get_disk

    # 如果cpu数组为空则放弃上传
    if [ ${#cpu_usage[@]} -eq 0 ]; then
        return
    fi

    # 获取数组长度
    cpuCount=${#cpu_usage[@]}
    memCount=${#mem_used[@]}

    # 计算cpu的平均使用率
    local cpuSum=0
    local cpuAvg=0
    for usage in ${cpu_usage[@]}; do
        cpuSum=$(echo $cpuSum+$usage | bc)
    done
    # 取平均值
    cpuAvg=$(echo "scale=2; $cpuSum/$cpuCount" | bc)

    # 计算内存的平均使用率
    local memSum=0
    local memAvg=0
    for usage in ${mem_used[@]}; do
        memSum=$(echo $memSum+$usage | bc)
    done
    # 取平均值
    memAvg=$(echo "scale=2; $memSum/$memCount" | bc)

    # 构造要发送的数据结构
    local json_data=$(cat <<EOF
{
    "server": "${SERVERNAME}",
    "cpu_c": ${cpuAvg},
    "cpu_m": ${CPU_MAX},
    "mem_c": ${memAvg},
    "mem_m": ${mem_total},
    "disk_c": ${disk_used},
    "disk_m": ${disk_total},
    "ts": $(date +%s)
}
EOF
    )

    # 清空数组
    cpu_usage=()
    mem_used=()

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

# 计算每次获取数据的间隔
# 对传参整数化
GETDATA_COUNT_MINUTE=$(echo $GETDATA_COUNT_MINUTE | awk '{print int($1)}')
# 如果执行失败,则退出程序
if [ $? -ne 0 ]; then
    echo "Error: The getdata_count_minute must be a number!" 1>&2
    exit 1
fi
# 值大于60则为60, 小于1则为1
if [ $GETDATA_COUNT_MINUTE -gt 60 ]; then
    GETDATA_COUNT_MINUTE=60
elif [ $GETDATA_COUNT_MINUTE -lt 1 ]; then
    GETDATA_COUNT_MINUTE=1
fi
# 计算每次获取数据的间隔
get_data_interval=$(echo $GETDATA_COUNT_MINUTE | awk '{print int(60/$1)}')
# 如果执行失败,则退出程序
if [ $? -ne 0 ]; then
    echo "Error: The getdata_count_minute must be a number!" 1>&2
    exit 1
fi
# 值小于1则为1
if [ $get_data_interval -lt 1 ]; then
    get_data_interval=1
fi
if [ "$debug" = true ]; then
    echo "Get data interval: ${get_data_interval} seconds"
fi

# 如果cpumax小于100则为100
CPU_MAX=$(echo $CPU_MAX | awk '{print int($1)}')
# 执行失败则退出程序
if [ $? -ne 0 ]; then
    echo "Error: The cpu_max must be a number!" 1>&2
    exit 1
fi
if [ $CPU_MAX -lt 100 ]; then
    CPU_MAX=100
fi
if [ "$debug" = true ]; then
    echo "CPU_MAX: ${CPU_MAX}"
fi

# 获取脚本启动时的时间戳
start_timestamp=$(date +%s)

# 计算下一个整分钟的时间戳
next_minute_timestamp=$(((start_timestamp/60+1)*60))

# 循环获取数据
while true; do
    # 采集数据
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
    if [ "$debug" = true ]; then
        echo "Sleep ${get_data_interval} seconds..."
    fi

    sleep $get_data_interval
done
