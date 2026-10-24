APP_NAME := Pennyworth
APP_BUNDLE := $(APP_NAME).app
SWIFT ?= swift

.DEFAULT_GOAL := all

.PHONY: all build test coverage app run clean help

all: app

build:
	$(SWIFT) build

test:
	$(SWIFT) test

coverage:
	$(SWIFT) test --enable-code-coverage

app:
	./build.sh

run: app
	open "$(APP_BUNDLE)" --args --show

clean:
	$(SWIFT) package clean
	rm -rf "$(APP_BUNDLE)"

help:
	@printf '%s\n' \
		'Pennyworth 构建命令：' \
		'' \
		'  make            构建 Release 并打包 Pennyworth.app' \
		'  make build      构建 Debug 可执行文件' \
		'  make test       运行测试' \
		'  make coverage   运行测试并启用代码覆盖率' \
		'  make app        构建 Release 并打包 Pennyworth.app' \
		'  make run        打包并启动应用，立即显示搜索窗口' \
		'  make clean      清理 SwiftPM 构建产物和 Pennyworth.app' \
		'  make help       显示此帮助'
