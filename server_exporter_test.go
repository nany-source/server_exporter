package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

// 测试新建cpuMemInfo
func TestNewInfo(t *testing.T) {
	// 创建一个新的info对象
	info := newInfo()
	// 检查info对象是否不为空
	if info == nil {
		t.Fatalf("newInfo() = nil; want non-nil")
	}
}

// 测试清空cpuMemInfo的数据
func TestClear(t *testing.T) {
	// 创建一个新的info对象，设置一些数据
	info := newInfo()
	info.timestamp = 12345
	info.Cpu.Total = 100
	info.Cpu.UsageList = append(info.Cpu.UsageList, 10.0)
	// 清空info对象
	info.clear()
	// 检查info对象是否被清空
	if info.timestamp != 0 || info.Cpu.Total != 0 || len(info.Cpu.UsageList) != 0 {
		t.Errorf("clear() did not clear the fields")
	}
}

// 测试深克隆cpuMemInfo
func TestClone(t *testing.T) {
	// 创建一个新的info对象，设置一些数据
	info := newInfo()
	info.timestamp = 12345
	info.Cpu.Total = 100
	info.Cpu.UsageList = append(info.Cpu.UsageList, 10.0)
	// 克隆info对象
	cloned := info.clone()
	// 清空info对象
	info.clear()
	// 检查克隆的对象是否没被清空所影响
	if cloned.timestamp != 12345 || cloned.Cpu.Total != 100 || len(cloned.Cpu.UsageList) != 1 {
		t.Errorf("clone() did not clone the fields correctly")
	}
}

// 检查平均数计算是否正确
func TestCalculateAverage(t *testing.T) {
	// 测试数据
	list := []uint64{1, 2, 3, 4, 5}
	// 计算平均数
	avg := calculateAverage(list)
	// 检查平均数是否正确
	if avg != 3.0 {
		t.Errorf("calculateAverage() = %v; want 3.0", avg)
	}
}

// 测试读取配置文件
func TestLoadConfig(t *testing.T) {
	// 创建一个临时的配置文件
	configData := `{"server_name": "test_server", "endpoint": "http://localhost", "app_token": "token", "app_secret": "secret"}`
	tmpfile, err := os.CreateTemp("", "config.json")
	if err != nil {
		t.Fatal(err)
	}
	// 函数结束后删除临时文件
	defer os.Remove(tmpfile.Name())
	// 写入配置文件
	if _, err := tmpfile.Write([]byte(configData)); err != nil {
		t.Fatal(err)
	}
	// 关闭文件
	if err := tmpfile.Close(); err != nil {
		t.Fatal(err)
	}

	// 读取配置文件
	config, err := loadConfig(tmpfile.Name())
	if err != nil {
		t.Fatalf("loadConfig() error = %v", err)
	}
	// 检查配置文件是否正确
	if config.ServerName != "test_server" {
		t.Errorf("loadConfig() ServerName = %v; want test_server", config.ServerName)
	}
}

// 测试获取内存信息
func TestGetMemInfo(t *testing.T) {
	// 获取内存信息
	total, used, err := getMemInfo()
	if err != nil {
		t.Fatalf("getMemInfo() error = %v", err)
	}
	// 检查内存信息是否正确
	if total == 0 || used == 0 {
		t.Errorf("getMemInfo() = (%v, %v); want non-zero values", total, used)
	}
}

// 测试获取cpu时间
func TestGetCpuTimes(t *testing.T) {
	// 获取cpu信息
	total, idle, err := getCpuTimes()
	if err != nil {
		t.Fatalf("getCpuTimes() error = %v", err)
	}
	// 检查cpu信息是否正确
	if total == 0 || idle == 0 {
		t.Errorf("getCpuTimes() = (%v, %v); want non-zero values", total, idle)
	}
}

// 测试获取磁盘信息
func TestGetDiskInfo(t *testing.T) {
	// 获取磁盘信息
	size, used, err := getDiskInfo()
	if err != nil {
		t.Fatalf("getDiskInfo() error = %v", err)
	}
	// 检查磁盘信息是否正确
	if size == 0 || used == 0 {
		t.Errorf("getDiskInfo() = (%v, %v); want non-zero values", size, used)
	}
}

func TestGatherData(t *testing.T) {
	// 清除数据
	cpuMemInfo.clear()
	// 获取数据
	gatherData()
	// 检查数据是否正确
	if cpuMemInfo.timestamp == 0 || cpuMemInfo.Cpu.Total == 0 || cpuMemInfo.isFirstgather == true || cpuMemInfo.Mem.Total == 0 || len(cpuMemInfo.Mem.UsedList) == 0 {
		t.Errorf("gatherData() did not gather the data")
	}
}

// 模拟 HTTP 服务器 接受updata请求
func TestUploadData(t *testing.T) {
	// 清除数据
	cpuMemInfo.clear()

	// 配置测试服务器
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		// 输出请求体的数据
		var data map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
			t.Fatalf("json.NewDecoder().Decode() error = %v", err)
		}
		if data["cpu_c"].(float64) != 2000 || data["cpu_m"].(float64) != 10000 || data["mem_c"].(float64) != 200 || data["mem_m"].(float64) != 0 {
			t.Errorf("uploadData() = %v; want cpu_c=2000, cpu_m=10000, mem_c=200, mem_m=0", data)
		}
		// 返回成功
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{"code": 0, "message": "success"})
	}))
	defer ts.Close()

	// 配置
	config := &Settings{
		ServerName: "test_server",
		EndPoint:   ts.URL,
		AppToken:   "token",
		AppSecret:  "secret",
	}
	// 创建一个http客户端和缓冲区
	client := &http.Client{}
	buffer := bytes.NewBuffer([]byte{})

	// 填充数据
	mu.Lock()
	cpuMemInfo.timestamp = uint64(time.Now().Unix())
	cpuMemInfo.Cpu.UsageList = []float64{10.0, 20.0, 30.0}
	cpuMemInfo.Mem.UsedList = []uint64{100, 200, 300}
	mu.Unlock()

	// 上传数据
	uploadData(config, client, buffer)
}
