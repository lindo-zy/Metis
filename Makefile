export ARCHS = arm64 arm64e

# Metis 统一构建入口。TARGET/THEOS_PACKAGE_SCHEME 由根 build.sh 按
# ios16 / ios17 双目标覆盖；这里给出与 ios16 目标一致的默认值。
TARGET ?= iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide
export TARGET THEOS_PACKAGE_SCHEME

export DEBUG = 0
export FINALPACKAGE = 1

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Core
SUBPROJECTS += Runtime/SpringBoard
SUBPROJECTS += Runtime/UIKitHost
SUBPROJECTS += Runtime/PasteServices
SUBPROJECTS += Preferences/Shell
# 模块迁入时逐个启用：
# SUBPROJECTS += Preferences/CapturePages
# SUBPROJECTS += Preferences/KeyboardPages
# SUBPROJECTS += Preferences/ClipboardPages

include $(THEOS_MAKE_PATH)/aggregate.mk
