THEOS ?= $(HOME)/theos

ARCHS = arm64 arm64e

TARGET = iphone:clang:latest:13.0

TWEAK_NAME = FloatingButtonTweak

FloatingButtonTweak_FILES = Tweak.xm

FloatingButtonTweak_FRAMEWORKS = UIKit Foundation CoreGraphics

# 添加 -Wno-unused-variable 忽略未使用变量警告
FloatingButtonTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
