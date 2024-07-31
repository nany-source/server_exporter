package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

var (
	version    string      = "unknown"
	cpuMemInfo *CpuMemInfo = newInfo()
	response   *Response
	mu         sync.Mutex
	wg         sync.WaitGroup                       // 等待组
	uploadChan chan struct{}  = make(chan struct{}) // 上传器通道
	exitChan   chan struct{}  = make(chan struct{}) // 退出通道
)

// 配置文件
type Settings struct {
	ServerName string `json:"server_name"`
	EndPoint   string `json:"endpoint"`
	AppToken   string `json:"app_token"`
	AppSecret  string `json:"app_secret"`
}

// cpu和内存的信息
type CpuMemInfo struct {
	timestamp     uint64
	isFirstgather bool
	Cpu           *CpuInfo
	Mem           *MemInfo
}
type CpuInfo struct {
	Total     uint64
	Idle      uint64
	UsageList []float64
}
type MemInfo struct {
	Total    uint64
	UsedList []uint64
}

// 请求返回体
type Response struct {
	Code   int         `json:"code"`
	Msg    string      `json:"message,omitempty"`
	Result interface{} `json:"result,omitempty"`
}

// 定义 Number 接口
type Number interface {
	int | int32 | int64 | uint | uint32 | uint64 | float32 | float64
}

// cpuMemInfo
func newInfo() *CpuMemInfo { // 创建
	return &CpuMemInfo{
		isFirstgather: true,
		Cpu: &CpuInfo{
			UsageList: []float64{},
		},
		Mem: &MemInfo{
			UsedList: []uint64{},
		},
	}
}
func (info *CpuMemInfo) clear() { // 清空
	info.timestamp = 0
	info.isFirstgather = true
	info.Cpu.Total = 0
	info.Cpu.Idle = 0
	info.Cpu.UsageList = info.Cpu.UsageList[:0]
	info.Mem.Total = 0
	info.Mem.UsedList = info.Mem.UsedList[:0]
}
func (list *CpuInfo) Average() float64 { // 计算cpu占用率的平均值
	return calculateAverage(list.UsageList)
}
func (list *MemInfo) Average() float64 { // 计算内存占用平均值
	return calculateAverage(list.UsedList)
}
func (info *CpuMemInfo) clone() *CpuMemInfo { // 克隆
	return &CpuMemInfo{
		timestamp:     info.timestamp,
		isFirstgather: info.isFirstgather,
		Cpu: &CpuInfo{
			Total:     info.Cpu.Total,
			Idle:      info.Cpu.Idle,
			UsageList: append([]float64{}, info.Cpu.UsageList...),
		},
		Mem: &MemInfo{
			Total:    info.Mem.Total,
			UsedList: append([]uint64{}, info.Mem.UsedList...),
		},
	}
}

// 平均数的泛型函数，支持任何数值类型
func calculateAverage[T Number](list []T) float64 {
	// 如果数组大小为0, 返回0
	if len(list) == 0 {
		return float64(0)
	}

	// 计算总和
	var sum T
	for _, value := range list {
		sum += value
	}

	// 计算平均值
	return float64(float64(sum) / float64(len(list)))
}

// 获取当前时间的分钟数
func getMinute() int64 {
	return (time.Now().Unix() / 60) % 60
}

// 读取配置文件
func loadConfig(filename string) (*Settings, error) {
	config := &Settings{}

	buf, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	if err = json.Unmarshal(buf, config); err != nil {
		return nil, err
	}

	return config, nil
}

// 收集数据
func gatherData() {
	// 函数结束时通知等待组已完成
	defer wg.Done()

	// 每6秒执行一次
	ticker := time.NewTicker(6 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-uploadChan:
			// 收到上传器通道的信号, 则退出循环
			log.Println("Upload routine stopped! Gathering routine will exit.")
			return
		case <-ticker.C:
			// 获取内存占用率
			memTotal, memUsed, err := getMemInfo()
			if err != nil {
				log.Println("Error getting memory info: ", err.Error())
				continue
			}
			// 获取cpu信息
			cpuTotal, cpuIdle, err := getCpuTimes()
			if err != nil {
				log.Println("Error getting cpu info: ", err.Error())
				continue
			}

			// 上互斥锁
			mu.Lock()
			if cpuMemInfo.timestamp == 0 {
				cpuMemInfo.timestamp = uint64(time.Now().Unix())
			}

			// 内存占用率写入数组
			if memUsed > 0 {
				cpuMemInfo.Mem.Total = memTotal
				cpuMemInfo.Mem.UsedList = append(cpuMemInfo.Mem.UsedList, memUsed)
			}
			// 计算cpu占用率
			if cpuTotal > 0 {
				// 首次收集因为没多于1个的时间线收集, 则不计算cpu占用率
				if cpuMemInfo.isFirstgather {
					cpuMemInfo.Cpu.Total = cpuTotal
					cpuMemInfo.Cpu.Idle = cpuIdle
					cpuMemInfo.isFirstgather = false
				} else {
					// 存在则计算2个时间段内的cpu占用率
					totalDIff := cpuTotal - cpuMemInfo.Cpu.Total
					idleDiff := cpuIdle - cpuMemInfo.Cpu.Idle
					cpuMemInfo.Cpu.UsageList = append(cpuMemInfo.Cpu.UsageList, float64(totalDIff-idleDiff)/float64(totalDIff)*100)

					// 把当前时间赋值给上一次时间
					cpuMemInfo.Cpu.Total = cpuTotal
					cpuMemInfo.Cpu.Idle = cpuIdle
				}
			}
			// 解除互斥锁
			mu.Unlock()
			// log.Println("Data gathered successfully!", cpuMemInfo.Cpu.UsageList, cpuMemInfo.Mem.UsedList)
		}
	}
}

// 上传数据协程
func uploadDataRoutine(minute *int64, config *Settings, client *http.Client, buffer *bytes.Buffer) {
	// 函数结束时通知等待组已完成
	defer wg.Done()

	// 每秒执行一次的定时器
	ticker := time.NewTicker(1 * time.Second)
	// 函数结束时关闭定时器
	defer ticker.Stop()

	// 标记是否程序需要被停止
	isShutdown := false
	// 函数结束时关闭通道, 通知收集器停止收集数据
	defer close(uploadChan)

	for {
		select {
		// 如果程序需要停止, 则标记为停止
		case <-exitChan:
			log.Println("Program will exit. UploadData complete will exit.")
			isShutdown = true
			// 停止监听
			exitChan = nil
		case <-ticker.C:
			// 获取当前分钟数
			nowMinute := getMinute()
			// 如果当前分钟和上次一样, 则不进行处理.
			if nowMinute == *minute {
				continue
			}

			// 把当前分钟赋值给上次分钟
			*minute = nowMinute
			// 上传数据
			uploadData(config, client, buffer)

			// 如果程序需要停止, 则退出循环
			if isShutdown {
				return
			}
		}
	}
}

// 上传数据
func uploadData(config *Settings, client *http.Client, buffer *bytes.Buffer) {
	// 上互斥锁
	mu.Lock()
	// clone内容
	cpuMemInfoData := cpuMemInfo.clone()
	// 清空info的内容
	cpuMemInfo.clear()
	// 解除互斥锁
	mu.Unlock()

	// 如果cpu数组为空, 则不上传数据
	if len(cpuMemInfoData.Cpu.UsageList) == 0 {
		log.Println("No data to send!")
		return
	}

	// 获取磁盘信息
	diskSize, diskUsed, err := getDiskInfo()
	if err != nil {
		log.Println("Error getting disk info: ", err)
		return
	}

	// 构建 JSON 数据
	data := map[string]interface{}{
		"ts":     cpuMemInfoData.timestamp,
		"server": config.ServerName,
		"cpu_c":  cpuMemInfoData.Cpu.Average() * 100,
		"cpu_m":  10000,
		"mem_c":  cpuMemInfoData.Mem.Average(),
		"mem_m":  cpuMemInfoData.Mem.Total,
		"disk_c": diskUsed,
		"disk_m": diskSize,
	}
	jsonData, err := json.Marshal(data)
	// 构建错误, 打印错误信息并退出
	if err != nil {
		log.Println("Error marshalling data: ", err)
		return
	}

	// 重置并写入buffer
	buffer.Reset()
	buffer.Write(jsonData)

	// 创建新的post请求
	req, err := http.NewRequest("POST", config.EndPoint, buffer)
	// 创建错误, 打印错误信息并退出
	if err != nil {
		log.Println("Error creating request: ", err)
		return
	}

	// 设置头部信息
	req.Header.Set("APP-KEY", config.AppToken)
	req.Header.Set("APP-TOKEN", config.AppSecret)
	req.Header.Set("Content-Type", "application/json")

	// 发送设置好的请求
	resp, err := client.Do(req)
	// 产生错误, 打印错误信息并退出
	if err != nil {
		log.Println("Error sending metrics: ", err)
		return
	}
	// 结束函数时关闭响应体
	defer resp.Body.Close()

	// 发送成功, 解析响应体. 如果code不为0则为失败
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Println("Error reading response body: ", err)
		return
	}

	// 判断响应体的code如果不为0则返回错误信息
	err = json.Unmarshal(body, &response)
	if err != nil {
		log.Println("Error unmarshalling response: ", err)
		return
	}
	if response.Code != 0 {
		log.Println("Error sending metrics: ", response.Msg)
		return
	}

	log.Println("Metrics sent successfully to " + config.EndPoint)
}

func exitRoutine() {
	// 函数结束时通知等待组已完成
	defer wg.Done()

	// 获取当前时间并算出第二天0时的时间
	now := time.Now()
	tomorrow := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, now.Location())
	// tomorrow := now.Add(10 * time.Second) //测试用
	// 计算一次性定时器的时间
	shutdownTimer := time.NewTimer(tomorrow.Sub(now))
	// 定时器结束时关闭一次性定时器
	defer shutdownTimer.Stop()

	// golang 时间format必须为此字符串
	// 2006-01-02 15:04:05 可以对年月日时分秒分别拆分为一个独立的数字格式,拆分后的数字都是独立的,都分别代表对应位置的日期.
	// 2006表示4位年份,06表示2位年份
	// 01表示2位月份，1表示不带0的月份
	// 02表示2位日期，2表示不带0的日期
	// 15表示小时
	// 04表示分钟, 4表示不带0的分钟
	// 05表示秒, 5表示不带0的秒
	log.Println("Server Exporter will shutdown at:", tomorrow.Format("2006-01-02 15:04:05"))

	// 等待一次性计时器的信号
	for range shutdownTimer.C {
		// 通知上传器停止
		close(exitChan)
		log.Println("Server Exporter shutdown time reached. Upload the last data and exit.")
		return
	}
}

// 获取cpu时间 从 /proc/stat 文件中获取
// 返回值：total, idle, error (失败返回0)
func getCpuTimes() (uint64, uint64, error) {
	// 执行shell命令获取CPU时间
	out, err := exec.Command("sh", "-c", "cat /proc/stat | grep '^cpu ' | awk '{printf \"%u %u\", $2+$3+$4+$5+$6+$7+$8+$9, $5}'").Output()
	if err != nil {
		return 0, 0, err
	}

	// 解析输出
	var total, idle uint64
	_, err = fmt.Sscanf(string(out), "%d %d", &total, &idle)

	return total, idle, err
}

// 获取磁盘的总大小和使用的空间
// 返回值：size, used, error (失败返回0)
func getDiskInfo() (uint64, uint64, error) {
	// 执行shell命令获取磁盘信息
	out, err := exec.Command("sh", "-c", "df -B1 / | grep / | awk '{printf \"%u %u\", $2, $3}'").Output()
	if err != nil {
		return 0, 0, err
	}

	// 解析输出
	var size, used uint64
	_, err = fmt.Sscanf(string(out), "%d %d", &size, &used)
	return size, used, err
}

// 获取内存占用数
// 返回值：total, used, error (失败返回0)
func getMemInfo() (uint64, uint64, error) {
	// 执行shell命令获取内存信息
	out, err := exec.Command("sh", "-c", "free | grep Mem | awk '{printf \"%u %u\", $2, $3}'").Output()
	if err != nil {
		return 0, 0, err
	}

	// 解析输出
	var total, used uint64
	_, err = fmt.Sscanf(string(out), "%d %d", &total, &used)
	return total, used, err
}

func main() {
	// 创建文件锁防止重复运行
	lock, err := os.Create("server_exporter.lock")
	if err != nil {
		log.Fatalf("Error creating lock file: %v", err)
	}
	// 程序退出时删除文件锁并关闭文件
	defer os.Remove("server_exporter.lock")
	defer lock.Close()

	// 创建独占文件锁
	fErr := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	// 文件锁创建失败，说明已经有程序在运行
	if fErr != nil {
		log.Fatalln("server_exporter is running")
	}
	// 程序退出时解锁文件
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)

	// 加载配置文件
	config, err := loadConfig("server_exporter.json")
	// 解析报错，打印错误信息并退出
	if err != nil {
		fmt.Printf("Error loading config: %v", err)
		return
	}

	// 显示启动信息
	fmt.Println("--------------------------------")
	fmt.Println("Server Exporter Started!")
	fmt.Println("Version:", version)
	fmt.Println("Server Name:", config.ServerName)
	fmt.Println("Metrics will be sent to:", config.EndPoint)
	fmt.Println("--------------------------------")

	// 创建http客户端
	client := &http.Client{}
	// 创建buffer对象
	buffer := bytes.NewBuffer([]byte{})
	minute := getMinute()

	// 创建收集器和上传器的协程
	wg.Add(3)
	go exitRoutine()
	go gatherData()
	go uploadDataRoutine(&minute, config, client, buffer)

	wg.Wait()
	// 所有协程结束后退出
	log.Println("Server Exporter exited. Goodbye!")
	os.Exit(0)
}
