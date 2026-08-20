// ============================================================
// FakeDeviceHook v2.0 - 整合《新设备插件逆向分析报告》
// 10大模块: IOKit/Sysctl/UIScreen/GPS/JailbreakBypass/
//           StoreKit/UA/IDFA/IDFV/NetworkCarrier
// 架构: Rootless (Dopamine/Palera1n) arm64/arm64e
// ============================================================

#import <UIKit/UIKit.h>
#import <IOKit/IOKitLib.h>
#import <CoreLocation/CoreLocation.h>
#import <StoreKit/StoreKit.h>
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>

// 全局配置 (非static, 允许NetworkSpoof.x通过extern访问)
NSDictionary *g_profile = nil;

static void loadProfile() {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/FakeDevice/Profiles/%@.plist", bundleId];
    g_profile = [NSDictionary dictionaryWithContentsOfFile:path];
}

// ============================================================
// 模块1: IOKit 硬件指纹 (序列号/ECID/UDID/电池参数/主板码)
// ============================================================
%hookf(CFTypeRef, IORegistryEntryCreateCFProperty, io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    if (!g_profile) return %orig;
    NSString *k = (__bridge NSString *)key;
    
    if ([k isEqualToString:@"IOPlatformSerialNumber"] && g_profile[@"serial_number"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"serial_number"];
    }
    if ([k isEqualToString:@"IOPlatformUUID"] && g_profile[@"hardware_uuid"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"hardware_uuid"];
    }
    if ([k isEqualToString:@"UniqueDeviceID"] && g_profile[@"udid"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"udid"];
    }
    if ([k isEqualToString:@"DieID"] || [k isEqualToString:@"ECID"]) {
        if (g_profile[@"ecid"]) return (__bridge_retained CFTypeRef)g_profile[@"ecid"];
    }
    if ([k isEqualToString:@"MLBSerialNumber"] && g_profile[@"mlb_serial"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"mlb_serial"];
    }
    if ([k isEqualToString:@"CycleCount"] && g_profile[@"battery_cycle"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"battery_cycle"];
    }
    if ([k isEqualToString:@"DesignCapacity"] && g_profile[@"battery_design_capacity"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"battery_design_capacity"];
    }
    if ([k isEqualToString:@"CurrentCapacity"] && g_profile[@"battery_current_capacity"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"battery_current_capacity"];
    }
    if ([k isEqualToString:@"Temperature"] && g_profile[@"battery_temperature"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"battery_temperature"];
    }
    if ([k isEqualToString:@"Voltage"] && g_profile[@"battery_voltage"]) {
        return (__bridge_retained CFTypeRef)g_profile[@"battery_voltage"];
    }
    return %orig;
}

// ============================================================
// 模块2: Sysctl 硬件层伪造 (hw.machine/hw.memsize/hw.ncpu/kern.boottime)
// ============================================================
%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (g_profile && name) {
        if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) {
            if (oldp && g_profile[@"hw_machine"]) {
                const char *val = [g_profile[@"hw_machine"] UTF8String];
                strncpy((char *)oldp, val, *oldlenp);
                return 0;
            }
        }
        if (strcmp(name, "hw.physmem") == 0 || strcmp(name, "hw.memsize") == 0) {
            if (oldp && g_profile[@"physmem"]) {
                uint64_t mem = [g_profile[@"physmem"] unsignedLongLongValue];
                memcpy(oldp, &mem, sizeof(mem));
                return 0;
            }
        }
        if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
            if (oldp && g_profile[@"cpu_cores"]) {
                int cores = [g_profile[@"cpu_cores"] intValue];
                memcpy(oldp, &cores, sizeof(cores));
                return 0;
            }
        }
        if (strcmp(name, "kern.boottime") == 0) {
            if (oldp && g_profile[@"boot_time"]) {
                struct timeval tv;
                tv.tv_sec = [g_profile[@"boot_time"] longValue];
                tv.tv_usec = 0;
                memcpy(oldp, &tv, sizeof(tv));
                return 0;
            }
        }
    }
    return %orig;
}

// ============================================================
// 模块3: 屏幕显示篡改 (UIScreen bounds/scale/nativeScale/maxFPS)
// ============================================================
%hook UIScreen
- (CGRect)bounds {
    if (g_profile[@"pt_width"] && g_profile[@"pt_height"]) {
        return CGRectMake(0, 0, [g_profile[@"pt_width"] doubleValue], [g_profile[@"pt_height"] doubleValue]);
    }
    return %orig;
}
- (CGFloat)scale {
    if (g_profile[@"scale"]) {
        return [g_profile[@"scale"] doubleValue];
    }
    return %orig;
}
- (CGFloat)nativeScale {
    if (g_profile[@"scale"]) {
        return [g_profile[@"scale"] doubleValue];
    }
    return %orig;
}
- (NSInteger)maximumFramesPerSecond {
    if (g_profile[@"max_fps"]) {
        return [g_profile[@"max_fps"] integerValue];
    }
    return %orig;
}
%end

// ============================================================
// 模块4: GPS 定位伪造与微米级漂移 (防静态坐标风控)
// ============================================================
%hook CLLocationManager
- (CLLocation *)location {
    CLLocation *orig = %orig;
    if (!g_profile[@"latitude"]) return orig;
    
    double lat = [g_profile[@"latitude"] doubleValue];
    double lon = [g_profile[@"longitude"] doubleValue];
    
    // 微米级动态抖动算法
    double driftLat = ((double)arc4random_uniform(200) - 100.0) / 1000000.0;
    double driftLon = ((double)arc4random_uniform(200) - 100.0) / 1000000.0;

    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat + driftLat, lon + driftLon)
                                         altitude:20.0
                               horizontalAccuracy:5.0
                                 verticalAccuracy:5.0
                                        timestamp:[NSDate date]];
}
%end

// ============================================================
// 模块5: 越狱环境隐藏 (Bypass 14+ 常见检测路径)
// ============================================================
static BOOL is_jb_path(const char *path) {
    if (!path) return NO;
    static const char *jb_indicators[] = {
        "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
        "/Library/MobileSubstrate", "/usr/sbin/sshd", "/bin/bash", "/bin/sh",
        "/etc/apt", "/var/lib/apt", "/var/lib/cydia", "/User/Applications",
        "/usr/lib/libsubstitute.dylib", "/usr/lib/substrate", "/private/var/stash",
        "/var/jb", "/var/jb/usr/lib", "/var/jb/Library/MobileSubstrate"
    };
    for (int i = 0; i < sizeof(jb_indicators)/sizeof(char *); i++) {
        if (strstr(path, jb_indicators[i])) return YES;
    }
    return NO;
}

%hookf(int, stat, const char *path, struct stat *buf) {
    if (is_jb_path(path)) { errno = ENOENT; return -1; }
    return %orig;
}

%hookf(int, access, const char *path, int mode) {
    if (is_jb_path(path)) { errno = ENOENT; return -1; }
    return %orig;
}

// ============================================================
// 模块6: StoreKit 内购拦截与事务伪造
// ============================================================
%hook SKPaymentQueue
- (void)addPayment:(SKPayment *)payment {
    if ([g_profile[@"bypass_iap"] boolValue]) {
        %log;
        return;
    }
    %orig;
}
%end

// ============================================================
// 模块7: User-Agent 全局篡改 (通过 NSUserDefaults)
// ============================================================
%hook NSUserDefaults
- (NSString *)stringForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"UserAgent"] && g_profile[@"custom_ua"]) {
        return g_profile[@"custom_ua"];
    }
    return %orig;
}
%end

// ============================================================
// 模块8: IDFA 伪造 (ASIdentifierManager - 参考逆向报告第3节)
// 模板: 11111111-1234-1234-1234-12%@ 格式
// ============================================================
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (g_profile[@"fake_idfa"]) {
        return [[NSUUID alloc] initWithUUIDString:g_profile[@"fake_idfa"]];
    }
    // 动态构造: 固定前缀 + 随机后缀
    NSString *suffix = [NSString stringWithFormat:@"%012d", arc4random_uniform(1000000000)];
    NSString *fakeIDFA = [NSString stringWithFormat:@"11111111-1234-1234-1234-12%@", suffix];
    return [[NSUUID alloc] initWithUUIDString:fakeIDFA];
}
%end

// ============================================================
// 模块9: IDFV 伪造 (UIDevice identifierForVendor)
// ============================================================
%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (g_profile[@"fake_idfv"]) {
        return [[NSUUID alloc] initWithUUIDString:g_profile[@"fake_idfv"]];
    }
    // 动态构造: 固定前缀 + 随机后缀
    NSString *suffix = [NSString stringWithFormat:@"%012d", arc4random_uniform(1000000000)];
    NSString *fakeIDFV = [NSString stringWithFormat:@"22222222-1234-1234-1234-22%@", suffix];
    return [[NSUUID alloc] initWithUUIDString:fakeIDFV];
}
%end

// ============================================================
// 模块10: 本地凭证强力擦除引擎 (SSKeychain + removePersistentDomainForName)
// 参考《新设备插件》逆向报告 - 一键新机核心清理
// ============================================================
void executeDeepWipe(NSString *bundleId, NSString *sandboxPath) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // A. NSUserDefaults 域全量清空
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleId];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // B. Keychain 凭证安全擦除 (Generic/Internet/Cert/Key/Identity)
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

    // C. 沙盒目录深度清理 (Documents/Caches/Preferences/WebKit等)
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

%ctor {
    loadProfile();
}