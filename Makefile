# 针对 RootHide / Rootless 环境的标准配置
THEOS_DEVICE_IP = 127.0.0.1
THEOS_DEVICE_PORT = 2222

export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0

# 启用现代打包方案
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeDeviceHook
FakeDeviceHook_FILES = FakeDeviceTweak/Tweak.x
FakeDeviceHook_FRAMEWORKS = UIKit IOKit CoreLocation CoreTelephony SystemConfiguration StoreKit AdSupport
FakeDeviceHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unused-variable -Wno-unused-function

include $(THEOS_MAKE_PATH)/tweak.mk