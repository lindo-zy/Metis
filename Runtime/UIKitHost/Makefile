TWEAK_NAME = MetisUIKit

# UIKit 宿主（filter 见 MetisUIKit.plist：com.apple.UIKit，含 SpringBoard；
# constructor 内对 SpringBoard 立即 return，保证按进程最小注入）。
# 承载 TypeX 键盘与 Kayoko Helper 的统一 hook（03-architecture §1）。
MetisUIKit_FILES = MTUIKitEntry.xm

MetisUIKit_CFLAGS = -fobjc-arc
MetisUIKit_CFLAGS += -I../../Core
MetisUIKit_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
