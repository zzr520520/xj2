export THEOS = /opt/theos
export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = FakeDeviceSuite
FakeDeviceSuite_FILES = $(wildcard FakeDeviceApp/Sources/*.m)
FakeDeviceSuite_FRAMEWORKS = UIKit CoreGraphics Security
FakeDeviceSuite_PRIVATE_FRAMEWORKS = AppSupport
FakeDeviceSuite_CODESIGN_FLAGS = -Sentitlements.plist

TWEAK_NAME = FakeDeviceHook
FakeDeviceHook_FILES = FakeDeviceTweak/Tweak.x FakeDeviceTweak/NetworkSpoof.x
FakeDeviceHook_FRAMEWORKS = UIKit IOKit CoreLocation CoreTelephony Metal StoreKit WebKit
FakeDeviceHook_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# Build targets
all: clean package

clean:
	rm -rf packages/*.deb

package:
	@echo "Building FinalPackage..."
	@echo "Output: packages/com.research.fakedevicesuite_1.0.0_iphoneos-arm64.deb"