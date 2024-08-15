package exportLogger

import (
	"log"
	"os"
	"strings"
)

// 日志等级
const (
	DEBUG = iota
	INFO
	WARN
	ERROR
	SYSTEM
)

// 结构体
type Logger struct {
	level  int
	Logger *log.Logger
}

// 按照等级输出日志(私有方法)
func (l *Logger) logMessage(level int, message string) {
	if level >= l.level {
		l.Logger.Println(message)
	}
}

// 创建实例
func NewLogger(level int) *Logger {
	return &Logger{
		level:  level,
		Logger: log.New(os.Stdout, "", log.LstdFlags),
	}
}

// 根据文本返回日志等级(不区分大小写)
func GetLevelByText(level string) int {
	switch strings.ToLower(level) {
	case "debug":
		return DEBUG
	case "info":
		return INFO
	case "warn":
		return WARN
	case "error":
		return ERROR
	default:
		return INFO
	}
}

// 设置日志等级
func (l *Logger) SetLevel(level int) {
	l.level = level
}

// Debug
func (l *Logger) Debug(message string) {
	l.logMessage(DEBUG, "[DEBUG] "+message)
}

// Info
func (l *Logger) Info(message string) {
	l.logMessage(INFO, "[INFO] "+message)
}

// Warn 传参跟println一样多传
func (l *Logger) Warn(message string) {
	l.logMessage(WARN, "[WARN] "+message)
}

// Error
func (l *Logger) Error(message string) {
	l.logMessage(ERROR, "[ERROR] "+message)
}

// System
func (l *Logger) System(message string) {
	l.logMessage(SYSTEM, "[SYSTEM] "+message)
}
