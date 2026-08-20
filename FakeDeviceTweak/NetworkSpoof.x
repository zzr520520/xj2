// ============================================================
// NetworkSpoof.x - 网络模式与运营商独立伪造
// 支持: 无卡/飞行/移动/联通/电信/广电/WiFi模式
// ============================================================

#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <Network/Network.h>

extern NSDictionary *g_profile;

// ============================================================
// 1. CoreTelephony 蜂窝/无卡/运营商拦截
// ============================================================
%hook CTTelephonyNetworkInfo

- (CTCarrier *)subscriberCellularProvider {
    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"NO_SIM"] || [netMode isEqualToString:@"AIRPLANE"] || [netMode isEqualToString:@"WIFI_ONLY"]) {
        return nil;
    }
    return %orig;
}

- (NSDictionary<NSString *, CTCarrier *> *)serviceSubscriberCellularProviders {
    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"NO_SIM"] || [netMode isEqualToString:@"AIRPLANE"] || [netMode isEqualToString:@"WIFI_ONLY"]) {
        return @{};
    }
    return %orig;
}

- (NSString *)currentRadioAccessTechnology {
    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"NO_SIM"] || [netMode isEqualToString:@"AIRPLANE"] || [netMode isEqualToString:@"WIFI_ONLY"]) {
        return nil;
    }
    return g_profile[@"radio_tech"] ?: CTRadioAccessTechnologyLTE;
}

- (NSDictionary<NSString *, NSString *> *)serviceCurrentRadioAccessTechnology {
    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"NO_SIM"] || [netMode isEqualToString:@"AIRPLANE"] || [netMode isEqualToString:@"WIFI_ONLY"]) {
        return @{};
    }
    return @{@"0000000100000001": (g_profile[@"radio_tech"] ?: CTRadioAccessTechnologyNRNSA)};
}

%end

// ============================================================
// 2. 四大运营商属性精准匹配 (移动/联通/电信/广电)
// ============================================================
%hook CTCarrier

- (NSString *)carrierName {
    return g_profile[@"carrier_name"] ?: %orig;
}

- (NSString *)mobileCountryCode {
    return g_profile[@"mcc"] ?: %orig;
}

- (NSString *)mobileNetworkCode {
    return g_profile[@"mnc"] ?: %orig;
}

- (NSString *)isoCountryCode {
    return g_profile[@"iso_country"] ?: @"cn";
}

- (BOOL)allowsVOIP {
    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"NO_SIM"] || [netMode isEqualToString:@"AIRPLANE"]) return NO;
    return YES;
}

%end

// ============================================================
// 3. 飞行模式与网络可达性底层拦截 (SCNetworkReachability)
// ============================================================
%hookf(Boolean, SCNetworkReachabilityGetFlags, SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    if (!flags) return %orig;

    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"AIRPLANE"]) {
        *flags = 0;
        return TRUE;
    } else if ([netMode isEqualToString:@"WIFI_ONLY"]) {
        *flags = kSCNetworkReachabilityFlagsReachable;
        return TRUE;
    } else if ([netMode hasPrefix:@"CHINA_"] || [netMode isEqualToString:@"CELLULAR"]) {
        *flags = kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN;
        return TRUE;
    }

    return %orig;
}

// ============================================================
// 4. Wi-Fi 模式与硬件 MAC/BSSID 深度伪造
// ============================================================
%hookf(CFArrayRef, CNCopySupportedInterfaces) {
    NSString *netMode = g_profile[@"network_mode"];
    if ([netMode isEqualToString:@"AIRPLANE"]) {
        return NULL;
    }
    return %orig;
}

%hookf(CFDictionaryRef, CNCopyCurrentNetworkInfo, CFStringRef interfaceName) {
    NSString *netMode = g_profile[@"network_mode"];

    if ([netMode isEqualToString:@"AIRPLANE"] || [g_profile[@"disable_wifi_leak"] boolValue]) {
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