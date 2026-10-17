TWEAK_NAME = MetisSpringBoard

# 仅 SpringBoard（filter 见 MetisSpringBoard.plist）。承载 PixPin/TypeX 系统
# 能力/Kayoko Core 与模块注册（03-architecture §1）。源清单显式列出，禁止
# 顶层通配把 Prefs/stub 编进注入目标。
MetisSpringBoard_FILES = MTSpringBoardEntry.xm

MetisSpringBoard_CFLAGS = -fobjc-arc
MetisSpringBoard_CFLAGS += -I../../Core
MetisSpringBoard_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
