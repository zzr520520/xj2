// ============================================================
// FakeDeviceHook v3.0 - 防崩生产级 (RootHide/Rootless)
// 核心防崩: 进程隔离 + 系统黑名单 + 空指针守卫
// 严禁注入 SpringBoard, 仅允许第三方 App 进程
// ============================================================

#import <UIKit/UIKit.h>
#import <IOKit/IOKitLib.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <StoreKit/StoreKit.h>
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/stat.h>

// 全局配置与目标进程标识
NSDictionary *g_config = nil;
static BOOL g_isTargetApp = NO;

// ============================================================
// 1. 安全初始化: 严格过滤系统进程与 SpringBoard
// ============================================================
static void initSecurityCheck() {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleId) return;

    // 系统白名单: 绝对不注入桌面与核心系统服务
    NSArray *blacklist = @[
        @"com.apple.springboard",
        @"com.apple.backboardd",
        @"com.apple.Preferences",
        @"com.apple.mobilephone",
        @"com.apple.Search",
        @"org.coolstar.SileoStore",
        @"com.saurik.Cydia"
    ];

    for (NSString *item in blacklist) {
        if ([bundleId isEqualToString:item]) {
            g_isTargetApp = NO;
            return;
        }
    }

    // 读取配置 (支持 RootHide/Rootless 路径)
    NSString *confPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/FakeDevice_%@.plist", bundleId];
    if ([[NSFileManager defaultManager] fileExistsAtPath:confPath]) {
        g_config = [[NSDictionary alloc] initWithContentsOfFile:confPath];
        g_isTargetApp = [g_config[@"enabled"] boolValue];
    }
}

// ============================================================
// 2. 设备标识符伪造 (IDFA / IDFV / DeviceName / SystemVersion)
// ============================================================
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (g_isTargetApp && g_config[@"idfa"]) {
        return [[NSUUID alloc] initWithUUIDString:g_config[@"idfa"]];
    }
    return %orig;
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (g_isTargetApp && g_config[@"idfv"]) {
        return [[NSUUID alloc] initWithUUIDString:g_config[@"idfv"]];
    }
    return %orig;
}
- (NSString *)name {
    return (g_isTargetApp && g_config[@"device_name"]) ? g_config[@"device_name"] : %orig;
}
- (NSString *)systemVersion {
    return (g_isTargetApp && g_config[@"system_version"]) ? g_config[@"system_version"] : %orig;
}
%end

// ============================================================
// 3. 网络模式独立控制 (无卡/飞行/移动/联通/电信/广电/Wi-Fi)
// ============================================================
%hook CTTelephonyNetworkInfo

- (CTCarrier *)subscriberCellularProvider {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return nil;
    }
    return %orig;
}

- (NSDictionary<NSString *, CTCarrier *> *)serviceSubscriberCellularProviders {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return @{};
    }
    return %orig;
}

- (NSString *)currentRadioAccessTechnology {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return nil;
    }
    return g_config[@"radio_tech"] ?: CTRadioAccessTechnologyLTE;
}

- (NSDictionary<NSString *, NSString *> *)serviceCurrentRadioAccessTechnology {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return @{};
    }
    return @{@"0000000100000001": (g_config[@"radio_tech"] ?: CTRadioAccessTechnologyNRNSA)};
}

%end

%hook CTCarrier
- (NSString *)carrierName {
    return (g_isTargetApp && g_config[@"carrier_name"]) ? g_config[@"carrier_name"] : %orig;
}
- (NSString *)mobileCountryCode {
    return (g_isTargetApp && g_config[@"mcc"]) ? g_config[@"mcc"] : %orig;
}
- (NSString *)mobileNetworkCode {
    return (g_isTargetApp && g_config[@"mnc"]) ? g_config[@"mnc"] : %orig;
}
- (NSString *)isoCountryCode {
    return (g_isTargetApp && g_config[@"iso_country"]) ? g_config[@"iso_country"] : %orig;
}
- (BOOL)allowsVOIP {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE"]) return NO;
    return YES;
}
%end

// ============================================================
// 4. 飞行模式与网络可达性拦截 (SCNetworkReachability)
// ============================================================
%hookf(Boolean, SCNetworkReachabilityGetFlags, SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    if (!g_isTargetApp || !flags) return %orig;

    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"AIRPLANE"]) {
        *flags = 0;
        return TRUE;
    } else if ([mode isEqualToString:@"WIFI_ONLY"]) {
        *flags = kSCNetworkReachabilityFlagsReachable;
        return TRUE;
    } else if ([mode hasPrefix:@"CHINA_"] || [mode isEqualToString:@"CELLULAR"]) {
        *flags = kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN;
        return TRUE;
    }

    return %orig;
}

// ============================================================
// 5. Wi-Fi MAC/BSSID 深度伪造
// ============================================================
%hookf(CFArrayRef, CNCopySupportedInterfaces) {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];
    if ([mode isEqualToString:@"AIRPLANE"]) {
        return NULL;
    }
    return %orig;
}

%hookf(CFDictionaryRef, CNCopyCurrentNetworkInfo, CFStringRef interfaceName) {
    if (!g_isTargetApp) return %orig;
    NSString *mode = g_config[@"net_mode"];

    if ([mode isEqualToString:@"AIRPLANE"] || [g_config[@"disable_wifi_leak"] boolValue]) {
        return NULL;
    }

    if (g_config[@"wifi_ssid"] && g_config[@"wifi_bssid"]) {
        NSDictionary *wifiInfo = @{
            (__bridge NSString *)kCNNetworkInfoKeySSID: g_config[@"wifi_ssid"],
            (__bridge NSString *)kCNNetworkInfoKeyBSSID: g_config[@"wifi_bssid"],
            @"SSIDDATA": [g_config[@"wifi_ssid"] dataUsingEncoding:NSUTF8StringEncoding]
        };
        return (__bridge_retained CFDictionaryRef)wifiInfo;
    }

    return %orig;
}

// ============================================================
// 6. 定位伪造与微米漂移 (CoreLocation)
// ============================================================
%hook CLLocationManager
- (CLLocation *)location {
    if (g_isTargetApp && g_config[@"latitude"] && g_config[@"longitude"]) {
        double lat = [g_config[@"latitude"] doubleValue];
        double lon = [g_config[@"longitude"] doubleValue];

        // 抖动算法防死板数据检测
        double driftLat = ((double)arc4random_uniform(100) - 50.0) / 1000000.0;
        double driftLon = ((double)arc4random_uniform(100) - 50.0) / 1000000.0;
        return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat + driftLat, lon + driftLon)
                                             altitude:18.0
                                   horizontalAccuracy:5.0
                                     verticalAccuracy:5.0
                                            timestamp:[NSDate date]];
    }
    return %orig;
}
%end

// ============================================================
// 7. IOKit 硬件底层伪造 (序列号/电池健康度/UDID/ECID)
// ============================================================
%hookf(CFTypeRef, IORegistryEntryCreateCFProperty, io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    if (!g_isTargetApp || !g_config) return %orig;

    NSString *k = (__bridge NSString *)key;

    if ([k isEqualToString:@"IOPlatformSerialNumber"] && g_config[@"serial_number"]) {
        return (__bridge_retained CFTypeRef)g_config[@"serial_number"];
    }
    if ([k isEqualToString:@"IOPlatformUUID"] && g_config[@"hardware_uuid"]) {
        return (__bridge_retained CFTypeRef)g_config[@"hardware_uuid"];
    }
    if ([k isEqualToString:@"UniqueDeviceID"] && g_config[@"udid"]) {
        return (__bridge_retained CFTypeRef)g_config[@"udid"];
    }
    if ([k isEqualToString:@"DieID"] || [k isEqualToString:@"ECID"]) {
        if (g_config[@"ecid"]) return (__bridge_retained CFTypeRef)g_config[@"ecid"];
    }
    if ([k isEqualToString:@"MLBSerialNumber"] && g_config[@"mlb_serial"]) {
        return (__bridge_retained CFTypeRef)g_config[@"mlb_serial"];
    }
    if ([k isEqualToString:@"CycleCount"] && g_config[@"battery_cycle"]) {
        return (__bridge_retained CFTypeRef)g_config[@"battery_cycle"];
    }
    if ([k isEqualToString:@"DesignCapacity"] && g_config[@"battery_design_capacity"]) {
        return (__bridge_retained CFTypeRef)g_config[@"battery_design_capacity"];
    }
    if ([k isEqualToString:@"CurrentCapacity"] && g_config[@"battery_current_capacity"]) {
        return (__bridge_retained CFTypeRef)g_config[@"battery_current_capacity"];
    }
    if ([k isEqualToString:@"Temperature"] && g_config[@"battery_temperature"]) {
        return (__bridge_retained CFTypeRef)g_config[@"battery_temperature"];
    }
    if ([k isEqualToString:@"Voltage"] && g_config[@"battery_voltage"]) {
        return (__bridge_retained CFTypeRef)g_config[@"battery_voltage"];
    }
    return %orig;
}

// ============================================================
// 8. Sysctl 硬件层伪造 (hw.machine/memsize/ncpu/boottime)
// ============================================================
%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (g_isTargetApp && g_config && name) {
        if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) {
            if (oldp && g_config[@"hw_machine"]) {
                const char *val = [g_config[@"hw_machine"] UTF8String];
                strncpy((char *)oldp, val, *oldlenp);
                return 0;
            }
        }
        if (strcmp(name, "hw.physmem") == 0 || strcmp(name, "hw.memsize") == 0) {
            if (oldp && g_config[@"physmem"]) {
                uint64_t mem = [g_config[@"physmem"] unsignedLongLongValue];
                memcpy(oldp, &mem, sizeof(mem));
                return 0;
            }
        }
        if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
            if (oldp && g_config[@"cpu_cores"]) {
                int cores = [g_config[@"cpu_cores"] intValue];
                memcpy(oldp, &cores, sizeof(cores));
                return 0;
            }
        }
        if (strcmp(name, "kern.boottime") == 0) {
            if (oldp && g_config[@"boot_time"]) {
                struct timeval tv;
                tv.tv_sec = [g_config[@"boot_time"] longValue];
                tv.tv_usec = 0;
                memcpy(oldp, &tv, sizeof(tv));
                return 0;
            }
        }
    }
    return %orig;
}

// ============================================================
// 9. 屏幕显示篡改 (UIScreen bounds/scale/nativeScale/maxFPS)
// ============================================================
%hook UIScreen
- (CGRect)bounds {
    if (g_isTargetApp && g_config[@"pt_width"] && g_config[@"pt_height"]) {
        return CGRectMake(0, 0, [g_config[@"pt_width"] doubleValue], [g_config[@"pt_height"] doubleValue]);
    }
    return %orig;
}
- (CGFloat)scale {
    return (g_isTargetApp && g_config[@"scale"]) ? [g_config[@"scale"] doubleValue] : %orig;
}
- (CGFloat)nativeScale {
    return (g_isTargetApp && g_config[@"scale"]) ? [g_config[@"scale"] doubleValue] : %orig;
}
- (NSInteger)maximumFramesPerSecond {
    return (g_isTargetApp && g_config[@"max_fps"]) ? [g_config[@"max_fps"] integerValue] : %orig;
}
%end

// ============================================================
// 10. 越狱环境隐藏 (Bypass 17+ 检测路径含RootHide)
// ============================================================
static BOOL is_jb_path(const char *path) {
    if (!path) return NO;
    static const char *jb_indicators[] = {
        "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
        "/Library/MobileSubstrate", "/usr/sbin/sshd", "/bin/bash", "/bin/sh",
        "/etc/apt", "/var/lib/apt", "/var/lib/cydia", "/User/Applications",
        "/usr/lib/libsubstitute.dylib", "/usr/lib/substrate", "/private/var/stash",
        "/var/jb", "/var/jb/usr/lib", "/var/jb/Library/MobileSubstrate",
        "/var/LIY", "/var/LIY/"
    };
    for (int i = 0; i < sizeof(jb_indicators)/sizeof(char *); i++) {
        if (strstr(path, jb_indicators[i])) return YES;
    }
    return NO;
}

%hookf(int, stat, const char *path, struct stat *buf) {
    if (g_isTargetApp && is_jb_path(path)) { errno = ENOENT; return -1; }
    return %orig;
}

%hookf(int, access, const char *path, int mode) {
    if (g_isTargetApp && is_jb_path(path)) { errno = ENOENT; return -1; }
    return %orig;
}

// ============================================================
// 11. StoreKit 内购拦截
// ============================================================
%hook SKPaymentQueue
- (void)addPayment:(SKPayment *)payment {
    if (g_isTargetApp && [g_config[@"bypass_iap"] boolValue]) {
        %log;
        return;
    }
    %orig;
}
%end

// ============================================================
// 12. User-Agent 全局篡改
// ============================================================
%hook NSUserDefaults
- (NSString *)stringForKey:(NSString *)defaultName {
    if (g_isTargetApp && [defaultName isEqualToString:@"UserAgent"] && g_config[@"custom_ua"]) {
        return g_config[@"custom_ua"];
    }
    return %orig;
}
%end

// ============================================================
// 13. 本地凭证强力擦除引擎 (SSKeychain + removePersistentDomainForName)
// ============================================================
void executeDeepWipe(NSString *bundleId, NSString *sandboxPath) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // A. NSUserDefaults 域全量清空
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleId];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // B. Keychain 凭证安全擦除
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    for (id secClass in secClasses) {
        NSDictionary *query = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecAttrAccessGroup: bundleId
        };
        SecItemDelete((__bridge CFDictionaryRef)query);
    }

    // C. 沙盒目录深度清理
    NSArray *dirsToClean = @[
        @"Documents", @"Library/Caches", @"Library/Preferences",
        @"tmp", @"Library/WebKit", @"Library/Application Support",
        @"Library/Cookies", @"Library/Saved Application State", @"Library/HTTPStorages"
    ];
    for (NSString *sub in dirsToClean) {
        NSString *fullPath = [sandboxPath stringByAppendingPathComponent:sub];
        [fm removeItemAtPath:fullPath error:nil];
        [fm createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

// ============================================================
// 构造函数: 安全初始化
// ============================================================
%ctor {
    @autoreleasepool {
        initSecurityCheck();
    }
}