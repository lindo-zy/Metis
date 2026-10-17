TWEAK_NAME = MetisUIKit

# UIKit 宿主（filter 见 MetisUIKit.plist：com.apple.UIKit，含 SpringBoard；
# constructor 内对 SpringBoard 立即 return，保证按进程最小注入）。
# 承载 MetisKeyboard 键盘 hook 与 Kayoko Helper 的统一 hook（03-architecture §1）。
MetisUIKit_FILES = MTUIKitEntry.xm \
	$(THEOS_PROJECT_DIR)/Modules/Keyboard/Sources/MTKeyboardHooks.xm \
	../../Modules/Keyboard/Sources/MTPasteChip.m \

MetisUIKit_CFLAGS = -fobjc-arc
MetisUIKit_CFLAGS += -I../../Core
MetisUIKit_CFLAGS += -I../../Modules/Keyboard/Sources
MetisUIKit_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib
MetisUIKit_FRAMEWORKS = UIKit CoreGraphics QuartzCore ImageIO SafariServices PhotosUI UniformTypeIdentifiers JavaScriptCore
MetisUIKit_PRIVATE_FRAMEWORKS = AppSupport Preferences FrontBoardServices SpringBoardServices


# Clipboard（MetisClipboard Helper 迁入）：键盘宿主 hook（SwipeUp 识别器在 MetisCore）
HELPER = ../../Modules/Clipboard/Helper
MetisUIKit_FILES += $(filter-out $(HELPER)/MTSwipeUpGestureRecognizer.m,$(wildcard $(HELPER)/*.m))
MetisUIKit_FILES += $(wildcard $(HELPER)/*.mm)
MetisUIKit_CFLAGS += -I../../Modules/Clipboard/Helper -I../../Preferences/ClipboardPages
MetisUIKit_FRAMEWORKS += AudioToolbox
MetisUIKit_LIBRARIES += substrate
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MetisUIKit_LIBRARIES += roothide
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
