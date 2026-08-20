export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeDeviceHook
FakeDeviceHook_FILES = FakeDeviceTweak/Tweak.x FakeDeviceTweak/NetworkSpoof.x
FakeDeviceHook_FRAMEWORKS = UIKit IOKit CoreLocation CoreTelephony StoreKit SystemConfiguration
FakeDeviceHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new

include $(THEOS_MAKE_PATH)/tweak.mk