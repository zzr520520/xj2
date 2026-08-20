// ============================================================
// NetworkSettingViewController.m - 桌面端控制台网络模式切换
// 支持: 无卡/飞行/移动/联通/电信/广电/WiFi
// ============================================================

#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>

@interface NetworkSettingViewController : UIViewController
@property (nonatomic, strong) UISegmentedControl *netModeControl;
@property (nonatomic, strong) UITextField *ssidField;
@property (nonatomic, strong) UITextField *bssidField;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation NetworkSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"网络与运营商独立伪装";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 分段选择器: 无卡/飞行/移动/联通/电信/广电/Wi-Fi
    NSArray *items = @[@"无卡", @"飞行", @"移动", @"联通", @"电信", @"广电", @"Wi-Fi"];
    self.netModeControl = [[UISegmentedControl alloc] initWithItems:items];
    self.netModeControl.frame = CGRectMake(16, 100, self.view.bounds.size.width - 32, 40);
    [self.netModeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.netModeControl];

    // Wi-Fi SSID 输入框
    self.ssidField = [[UITextField alloc] initWithFrame:CGRectMake(16, 160, self.view.bounds.size.width - 32, 40)];
    self.ssidField.placeholder = @"Wi-Fi SSID (可选)";
    self.ssidField.borderStyle = UITextBorderStyleRoundedRect;
    [self.view addSubview:self.ssidField];

    // Wi-Fi BSSID 输入框
    self.bssidField = [[UITextField alloc] initWithFrame:CGRectMake(16, 210, self.view.bounds.size.width - 32, 40)];
    self.bssidField.placeholder = @"Wi-Fi BSSID (如: 3c:cd:57:a1:8f:2b)";
    self.bssidField.borderStyle = UITextBorderStyleRoundedRect;
    [self.view addSubview:self.bssidField];

    // 状态标签
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 270, self.view.bounds.size.width - 32, 30)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor systemGreenColor];
    self.statusLabel.text = @"当前模式: 默认";
    [self.view addSubview:self.statusLabel];

    // 一键新机按钮
    UIButton *wipeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    wipeButton.frame = CGRectMake(16, 320, self.view.bounds.size.width - 32, 50);
    [wipeButton setTitle:@"一键新机 (DeepWipe)" forState:UIControlStateNormal];
    wipeButton.backgroundColor = [UIColor systemRedColor];
    [wipeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    wipeButton.layer.cornerRadius = 10;
    [wipeButton addTarget:self action:@selector(executeWipe) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:wipeButton];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    NSArray *presetKeys = @[
        @"NO_SIM", @"AIRPLANE", @"CHINA_MOBILE",
        @"CHINA_UNICOM", @"CHINA_TELECOM", @"CHINA_BROADNET", @"WIFI_ONLY"
    ];
    NSString *selectedKey = presetKeys[sender.selectedSegmentIndex];
    [self applyNetworkPreset:selectedKey];
    self.statusLabel.text = [NSString stringWithFormat:@"当前模式: %@", selectedKey];
}

- (NSDictionary *)parametersForMode:(NSString *)mode {
    if ([mode isEqualToString:@"CHINA_MOBILE"]) {
        return @{
            @"network_mode": mode,
            @"carrier_name": @"中国移动",
            @"mcc": @"460",
            @"mnc": @"00",
            @"radio_tech": CTRadioAccessTechnologyNRNSA
        };
    } else if ([mode isEqualToString:@"CHINA_UNICOM"]) {
        return @{
            @"network_mode": mode,
            @"carrier_name": @"中国联通",
            @"mcc": @"460",
            @"mnc": @"01",
            @"radio_tech": CTRadioAccessTechnologyNRNSA
        };
    } else if ([mode isEqualToString:@"CHINA_TELECOM"]) {
        return @{
            @"network_mode": mode,
            @"carrier_name": @"中国电信",
            @"mcc": @"460",
            @"mnc": @"11",
            @"radio_tech": CTRadioAccessTechnologyNRNSA
        };
    } else if ([mode isEqualToString:@"CHINA_BROADNET"]) {
        return @{
            @"network_mode": mode,
            @"carrier_name": @"中国广电",
            @"mcc": @"460",
            @"mnc": @"15",
            @"radio_tech": CTRadioAccessTechnologyNR
        };
    }
    // NO_SIM, AIRPLANE, WIFI_ONLY
    return @{@"network_mode": mode};
}

- (void)applyNetworkPreset:(NSString *)presetKey {
    NSString *bundleId = @"com.target.app";
    NSString *confPath = [NSString stringWithFormat:@"/var/mobile/Library/FakeDevice/Profiles/%@.plist", bundleId];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:confPath] ?: [NSMutableDictionary dictionary];

    // 获取运营商参数
    NSDictionary *networkConfig = [self parametersForMode:presetKey];
    [dict addEntriesFromDictionary:networkConfig];

    // Wi-Fi 信息 (如果用户输入了)
    if (self.ssidField.text.length > 0) {
        dict[@"wifi_ssid"] = self.ssidField.text;
    }
    if (self.bssidField.text.length > 0) {
        dict[@"wifi_bssid"] = self.bssidField.text;
    }

    // 写入配置并持久化
    [dict writeToFile:confPath atomically:YES];

    // 通知 Tweak 刷新配置
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FakeDeviceProfileUpdated" object:nil];
}

- (void)executeWipe {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"一键新机"
                                                                   message:@"将清除目标App的所有本地数据(沙盒/Keychain/UserDefaults)，确定？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // 执行深度擦除 (通过外部调用 executeDeepWipe)
        NSString *bundleId = @"com.target.app";
        NSString *sandboxPath = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@", bundleId];
        // 通过 NSTask 或 system() 调用外部擦除脚本
        NSString *script = [NSString stringWithFormat:@"/usr/share/FakeDeviceSuite/wipe.sh %@", bundleId];
        system([script UTF8String]);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end