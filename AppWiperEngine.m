#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <sqlite3.h>
#include <signal.h>

@interface AppWiperEngine : NSObject
+ (void)wipeAppTarget:(NSString *)bundleId sandboxPath:(NSString *)containerPath;
@end

@implementation AppWiperEngine

+ (void)wipeAppTarget:(NSString *)bundleId sandboxPath:(NSString *)containerPath {
    // 1. 强杀目标进程及其守护子进程 (双保险 SIGKILL)
    NSString *killCmd = [NSString stringWithFormat:@"killall -9 %@", bundleId];
    system([killCmd UTF8String]);

    NSFileManager *fm = [NSFileManager defaultManager];

    // 2. 沙盒 15 个关键目录深度覆盖擦除
    NSArray *cleanDirs = @[
        @"Documents", @"Library/Caches", @"Library/Preferences", @"tmp",
        @"Library/WebKit", @"Library/Application Support", @"Library/Cookies",
        @"Library/Saved Application State", @"Library/HTTPStorages"
    ];
    for (NSString *sub in cleanDirs) {
        NSString *p = [containerPath stringByAppendingPathComponent:sub];
        [fm removeItemAtPath:p error:nil];
        [fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // 3. NSUserDefaults 域全量清除
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleId];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 4. Keychain 凭证安全擦除 (Generic/Internet/Cert/Key/Identity)
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

    // 5. TCC 数据库权限擦除 (麦克风、相机、定位、相册记录)
    sqlite3 *tccDb;
    if (sqlite3_open("/private/var/mobile/Library/TCC/TCC.db", &tccDb) == SQLITE_OK) {
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM access WHERE client = '%@';", bundleId];
        sqlite3_exec(tccDb, [sql UTF8String], NULL, NULL, NULL);
        sqlite3_close(tccDb);
    }

    // 6. CoreDuet / Biome 用户行为及启动画像痕迹清理
    [fm removeItemAtPath:@"/private/var/mobile/Library/Biome/streams/restricted" error:nil];
    [fm removeItemAtPath:@"/private/var/mobile/Library/CoreDuet" error:nil];
    [fm removeItemAtPath:@"/private/var/mobile/Library/Caches/com.apple.Pasteboard" error:nil];

    // 7. APNs 推送 Token 重置
    NSString *apsdPlist = [NSString stringWithFormat:@"/private/var/mobile/Library/Preferences/com.apple.apsd.%@.plist", bundleId];
    [fm removeItemAtPath:apsdPlist error:nil];
}

@end