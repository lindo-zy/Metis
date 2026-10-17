TWEAK_NAME = MetisPasteServices

# 仅 druid / pasted（filter 见 MetisPasteServices.plist）。
# 只承载用户启用时的粘贴提示兼容 hook（03-architecture §1）。
MetisPasteServices_FILES = MTPasteServicesEntry.xm \
	../../Modules/Clipboard/Core/MTPasteTipHooks.m

MetisPasteServices_CFLAGS = -fobjc-arc
MetisPasteServices_CFLAGS += -I../../Core -I../../Preferences/ClipboardPages
MetisPasteServices_LIBRARIES += substrate
MetisPasteServices_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
