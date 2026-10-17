BUNDLE_NAME = MetisKeyboardPrefs

# Keyboard（MetisKeyboard）详细设置子包：从统一设置壳的模块页进入。
# 共享 DX 类（含 vendored AltList）链接 MetisCore，保证 Preferences.app 内
# 类唯一定义；不再注册独立 PreferenceLoader 入口。
# /Library/Metis/Config 共享目录是键盘扩展沙盒读桥（keyboard-shared 快照 +
# keyboard-cache 图标缓存 + gate.plist 门控镜像；非权威配置源），0777 无 sticky：
# mobile 写者可原子替换 root 拥有的 staged 目录内容。
# 共享 DX 类全部链接 MetisCore（类唯一性见包检查 + 类清单审计）。
MetisKeyboardPrefs_FILES = $(wildcard *.m) $(wildcard *.mm)

MetisKeyboardPrefs_CFLAGS = -fobjc-arc
MetisKeyboardPrefs_CFLAGS += -Wno-tautological-pointer-compare
MetisKeyboardPrefs_CFLAGS += -I../../Modules/Keyboard/Sources -I../../Core
MetisKeyboardPrefs_CFLAGS += -DTYPEX_PACKAGE_VERSION=\"$(or $(PACKAGE_VERSION),$(THEOS_PACKAGE_BASE_VERSION))\"
MetisKeyboardPrefs_INSTALL_PATH = /Library/PreferenceBundles
MetisKeyboardPrefs_FRAMEWORKS = UIKit CoreGraphics SwiftUI MobileCoreServices JavaScriptCore UniformTypeIdentifiers
MetisKeyboardPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport
MetisKeyboardPrefs_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)test -n "$(PACKAGE_VERSION)" || { echo "error: PACKAGE_VERSION not set (use build.sh)" >&2; exit 1; }$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleShortVersionString -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisKeyboardPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleVersion -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisKeyboardPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/Metis/Config"$(ECHO_END)
	$(ECHO_NOTHING)chmod 0777 "$(THEOS_STAGING_DIR)/Library/Metis/Config"$(ECHO_END)
