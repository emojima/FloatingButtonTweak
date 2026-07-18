THEOS ?= $(HOME)/theos

ARCHS = arm64 arm64e

TARGET = iphone:clang:latest:13.0

TWEAK_NAME = FloatingButtonTweak

# 修改文件名：Tweak.xm -> Tweak.m（因为新代码是 .m 文件，不是 .xm 格式）
FloatingButtonTweak_FILES = Tweak.m

# 添加 JavaScriptCore 和 WebKit 框架
FloatingButtonTweak_FRAMEWORKS = UIKit Foundation CoreGraphics JavaScriptCore WebKit

# 添加 fishhook 库（用于替换 JSEvaluateScript 符号）
FloatingButtonTweak_LIBRARIES = fishhook

# 添加 -Wno-deprecated-declarations 和 -Wno-unused-variable 忽略警告
FloatingButtonTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
