TWEAK_NAME = MetisSpringBoard

# 仅 SpringBoard（filter 见 MetisSpringBoard.plist）。承载 PixPin、TypeX 系统
# 能力、Kayoko Core 与模块注册（03-architecture §1）。源清单按目录显式列出，
# 禁止顶层通配把 Prefs/stub 编进注入目标。
MetisSpringBoard_FILES = MTSpringBoardEntry.xm \
	MTCaptureModuleAdapter.m

# Capture（PixPin 迁入，04 §3）
MetisSpringBoard_FILES += $(wildcard ../../Modules/Capture/Sources/Common/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Capture/*.m) \
	$(wildcard ../../Modules/Capture/Sources/LongCapture/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Overlay/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Editor/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Output/*.m) \
	$(wildcard $(THEOS_PROJECT_DIR)/Modules/Capture/Sources/SpringBoard/*.xm)

MetisSpringBoard_CFLAGS = -fobjc-arc
MetisSpringBoard_CFLAGS += -I../../Core
MetisSpringBoard_CFLAGS += -I../../Modules/Capture/Sources/Common
MetisSpringBoard_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib
MetisSpringBoard_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreText Photos ImageIO

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
