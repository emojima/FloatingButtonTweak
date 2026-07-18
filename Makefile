THEOS ?= $(HOME)/theos

ARCHS = arm64 arm64e

TARGET = iphone:clang:latest:13.0

TWEAK_NAME = FloatingButtonTweak

FloatingButtonTweak_FILES = Tweak.m

FloatingButtonTweak_FRAMEWORKS = UIKit Foundation CoreGraphics JavaScriptCore WebKit

# 链接 Dobby 静态库（libdobby.a 放在项目根目录）
FloatingButtonTweak_LDFLAGS = $(THEOS_PROJECT_DIR)/libdobby.a

# 指定 Dobby 头文件路径（dobby.h 放在项目根目录）
FloatingButtonTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -I$(THEOS_PROJECT_DIR)

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
