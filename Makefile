# 使用环境变量 THEOS，GitHub Actions 中会设置
THEOS ?= $(HOME)/theos

ARCHS = arm64 arm64e

TARGET = iphone:clang:latest:13.0

TWEAK_NAME = FloatingButtonTweak

FloatingButtonTweak_FILES = Tweak.xm

FloatingButtonTweak_FRAMEWORKS = UIKit Foundation CoreGraphics

FloatingButtonTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
