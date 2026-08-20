#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <Network/Network.h>
#import <SystemConfiguration/CaptiveNetwork.h>

extern NSDictionary *g_profile;

// ============================================================
// 1. CoreTelephony 蜂窝/无卡/运营商拦截
// ============================================================
%hook CTTelephonyNetworkInfo

- (CTCarrier *)subscriberCellularProvider {
    NSString *mode = g_profile[@"network_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE_MODE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return nil;
    }
    return %orig;
}

- (NSDictionary<NSString *, CTCarrier *> *)serviceSubscriberCellularProviders {
    NSString *mode = g_profile[@"network_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE_MODE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return @{};
    }
    return %orig;
}

- (NSString *)currentRadioAccessTechnology {
    NSString *mode = g_profile[@"network_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE_MODE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return nil;
    }
    return g_profile[@"radioTech"] ?: CTRadioAccessTechnologyLTE;
}

- (NSDictionary<NSString *, NSString *> *)serviceCurrentRadioAccessTechnology {
    NSString *mode = g_profile[@"network_mode"];
    if ([mode isEqualToString:@"NO_SIM"] || [mode isEqualToString:@"AIRPLANE_MODE"] || [mode isEqualToString:@"WIFI_ONLY"]) {
        return @{};
    }
    return @{@"0000000100000001": (g_profile[@"radioTech"] ?: CTRadioAccessTechnologyNRNSA)};
}

%end

%hook CTCarrier

- (NSString *)carrierName {
    return g_profile[@"carrierName"] ?: %orig;
}

- (NSString *)mobileCountryCode {
    return g_profile[@"mobileCountryCode"] ?: %orig;
}

- (NSString *)mobileNetworkCode {
    return g_profile[@"mobileNetworkCode"] ?: %orig;
}

- (NSString *)isoCountryCode {
    return g_profile[@"isoCountryCode"] ?: %orig;
}

- (BOOL)allowsVOIP {
    return [g_profile[@"allowsVOIP"] boolValue];
}

%end

// ============================================================
// 2. SystemConfiguration 飞行模式与可达性伪装
// ============================================================
%hookf(Boolean, SCNetworkReachabilityGetFlags, SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    if (!flags) return %orig;

    NSString *mode = g_profile[@"network_mode"];
    if ([mode isEqualToString:@"AIRPLANE_MODE"]) {
        *flags = 0;
        return TRUE;
    } else if ([mode isEqualToString:@"WIFI_ONLY"]) {
        *flags = kSCNetworkReachabilityFlagsReachable;
        return TRUE;
    } else if ([mode hasPrefix:@"CHINA_"]) {
        *flags = kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN;
        return TRUE;
    }

    return %orig;
}

// ============================================================
// 3. Wi-Fi 模式与硬件 MAC/BSSID 深度伪造
// ============================================================
%hookf(CFArrayRef, CNCopySupportedInterfaces) {
    NSString *mode = g_profile[@"network_mode"];
    if ([mode isEqualToString:@"AIRPLANE_MODE"]) {
        return NULL;
    }
    return %orig;
}

%hookf(CFDictionaryRef, CNCopyCurrentNetworkInfo, CFStringRef interfaceName) {
    NSString *mode = g_profile[@"network_mode"];
    
    if ([mode isEqualToString:@"AIRPLANE_MODE"] || [g_profile[@"disable_wifi_leak"] boolValue]) {
        return NULL;
    }

    if (g_profile[@"wifi_ssid"] && g_profile[@"wifi_bssid"]) {
        NSDictionary *wifiInfo = @{
            (__bridge NSString *)kCNNetworkInfoKeySSID: g_profile[@"wifi_ssid"],
            (__bridge NSString *)kCNNetworkInfoKeyBSSID: g_profile[@"wifi_bssid"],
            @"SSIDDATA": [g_profile[@"wifi_ssid"] dataUsingEncoding:NSUTF8StringEncoding]
        };
        return (__bridge_retained CFDictionaryRef)wifiInfo;
    }

    return %orig;
}