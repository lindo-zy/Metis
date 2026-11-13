TWEAK_NAME = MetisSpringBoard

# 仅 SpringBoard（filter 见 MetisSpringBoard.plist）。承载 MetisCapture、MetisKeyboard 系统
# 能力、剪贴板核心与模块注册（03-architecture §1）。源清单按目录显式列出，
# 禁止顶层通配把 Prefs/stub 编进注入目标。
MetisSpringBoard_FILES = MTSpringBoardEntry.xm \
	MTCaptureModuleAdapter.m

MetisSpringBoard_FILES += ../../Modules/Charging/MTChargingSnapshot.m \
	../../Modules/Charging/MTChargingCardView.m \
	../../Modules/Charging/MTChargingRuntime.m

# Capture（MetisCapture 迁入，04 §3）
MetisSpringBoard_FILES += $(wildcard ../../Modules/Capture/Sources/Common/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Capture/*.m) \
	$(wildcard ../../Modules/Capture/Sources/LongCapture/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Overlay/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Editor/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Watermark/*.m) \
	$(wildcard ../../Modules/Capture/Sources/Output/*.m) \
	$(wildcard $(THEOS_PROJECT_DIR)/Modules/Capture/Sources/SpringBoard/*.xm)

MetisSpringBoard_CFLAGS = -fobjc-arc
MetisSpringBoard_CFLAGS += -I../../Core -I../../Core/SharedResources
MetisSpringBoard_CFLAGS += -I../../Modules/Capture/Sources/Common
MetisSpringBoard_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib
MetisSpringBoard_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreText Photos ImageIO IOSurface
MetisSpringBoard_FRAMEWORKS += CoreImage
MetisSpringBoard_FRAMEWORKS += Vision

# Keyboard（MetisKeyboard）SpringBoard 侧：服务/全局手势/悬浮托管/SMS
MetisSpringBoard_FILES += MTKeyboardSpringBoardEntry.xm \
	../../Modules/Keyboard/Sources/MTServer.m \
	../../Modules/Keyboard/Sources/MTSMSCodePolicy.m \
	$(THEOS_PROJECT_DIR)/Modules/Keyboard/Sources/MTEdgeGestureHooks.xm \
	$(THEOS_PROJECT_DIR)/Modules/Keyboard/Sources/MTArcGestureHooks.xm \
	../../Modules/Keyboard/Sources/MTEdgeDebugOverlay.m \
	../../Modules/Keyboard/Sources/MTArcDebugOverlay.m \
	$(THEOS_PROJECT_DIR)/Modules/Keyboard/Sources/MTGlobalPanelHooks.xm \
	$(THEOS_PROJECT_DIR)/Modules/Keyboard/Sources/MTSMSCodeHooks.xm

MetisSpringBoard_CFLAGS += -I../../Modules/Keyboard/Sources
MetisSpringBoard_FRAMEWORKS += SafariServices PhotosUI UniformTypeIdentifiers JavaScriptCore
MetisSpringBoard_PRIVATE_FRAMEWORKS = AppSupport FrontBoardServices SpringBoardServices


# Clipboard（MetisClipboard Core 迁入，04 §4）：面板/历史/采集/粘贴业务
MetisSpringBoard_FILES += MTClipboardModuleAdapter.m \
	$(wildcard ../../Modules/Clipboard/Core/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Manager/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Actions/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Controllers/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Coordinators/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Models/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Presentation/*.m) \
	$(wildcard ../../Modules/Clipboard/Core/Views/*.m)

# Rule model/engine lives in MetisCore, shared with Clipboard Preferences.
MetisSpringBoard_FILES := $(filter-out ../../Modules/Clipboard/Core/Actions/MTCaptureRuleEngine.m,$(MetisSpringBoard_FILES))

MetisSpringBoard_CFLAGS += -I../../Modules/Clipboard/Core \
	-I../../Modules/Clipboard/Core/Manager \
	-I../../Modules/Clipboard/Core/Actions \
	-I../../Modules/Clipboard/Shared/Actions \
	-I../../Modules/Clipboard/Core/Controllers \
	-I../../Modules/Clipboard/Core/Coordinators \
	-I../../Modules/Clipboard/Core/Models \
	-I../../Modules/Clipboard/Core/Presentation \
	-I../../Modules/Clipboard/Core/Views \
	-I../../Modules/Clipboard/Helper \
	-I../../Preferences/ClipboardPages
MetisSpringBoard_FRAMEWORKS += AudioToolbox AVFoundation IOKit Security
MetisSpringBoard_PRIVATE_FRAMEWORKS += CoreServices
MetisSpringBoard_LIBRARIES += sqlite3 substrate z
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MetisSpringBoard_LIBRARIES += roothide
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
