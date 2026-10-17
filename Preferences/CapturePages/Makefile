BUNDLE_NAME = MetisCapturePrefs

# Capture（MetisCapture）详细设置子包：从统一设置壳的模块页进入。
# 不再注册独立 PreferenceLoader 入口（原 PixPinPrefs.plist 不安装）。
MetisCapturePrefs_FILES = MTCaptureRootListController.m \
	MTEditorOrderController.m \
	MTEditorButtonEditController.m \
	MTCustomURLController.m \
	../../Modules/Capture/Sources/Common/MTConstants.m \
	../../Modules/Capture/Sources/Common/MTPanelAppearance.m \
	../../Modules/Capture/Sources/Common/MTEditorOrder.m \
	../../Modules/Capture/Sources/Common/MTSelectionToolbar.m \
	../../Modules/Capture/Sources/Common/MTCaptureLog.m \
	../../Modules/Capture/Sources/Editor/MTEditorLayout.m

MetisCapturePrefs_CFLAGS = -fobjc-arc
MetisCapturePrefs_CFLAGS += -I../../Modules/Capture/Sources/Common
MetisCapturePrefs_INSTALL_PATH = /Library/PreferenceBundles
MetisCapturePrefs_FRAMEWORKS = UIKit CoreGraphics QuartzCore
MetisCapturePrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk

# 版本同步：build.sh 传入本次实际包版本；只修改暂存资源，不回写源码模板。
internal-stage::
	$(ECHO_NOTHING)test -n "$(PACKAGE_VERSION)" || { echo "error: PACKAGE_VERSION not set (use build.sh)" >&2; exit 1; }$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleShortVersionString -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisCapturePrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleVersion -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisCapturePrefs.bundle/Info.plist"$(ECHO_END)
