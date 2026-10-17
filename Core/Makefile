LIBRARY_NAME = MetisCore

# MetisCore 是包内私有共享库：所有注入目标与设置子包都以动态链接使用它，
# 保证同一 Objective-C 类在一个进程内只有一个镜像定义（03-architecture §1）。
MetisCore_INSTALL_PATH = /Library/Metis/Frameworks
MetisCore_LDFLAGS += -install_name /var/jb/Library/Metis/Frameworks/MetisCore.dylib

MetisCore_FILES = MTLog.m \
	MTPathResolver.m \
	MTProcessContext.m \
	MTModuleGate.m \
	MTConfigService.m

MetisCore_CFLAGS = -fobjc-arc
MetisCore_CFLAGS += -DMETIS_PACKAGE_VERSION=\"$(or $(PACKAGE_VERSION),$(THEOS_PACKAGE_BASE_VERSION))\"
MetisCore_FRAMEWORKS = Foundation CoreFoundation

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MetisCore_LIBRARIES += roothide
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk
