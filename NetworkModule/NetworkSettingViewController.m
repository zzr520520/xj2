#import <UIKit/UIKit.h>

@interface NetworkSettingViewController : UIViewController
@property (nonatomic, strong) UISegmentedControl *netModeControl;
@property (nonatomic, strong) UITextField *ssidField;
@property (nonatomic, strong) UITextField *bssidField;
@end

@implementation NetworkSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"网络与运营商独立伪装";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    NSArray *items = @[@"无卡", @"飞行", @"移动", @"联通", @"电信", @"广电", @"Wi-Fi"];
    self.netModeControl = [[UISegmentedControl alloc] initWithItems:items];
    self.netModeControl.frame = CGRectMake(16, 100, self.view.bounds.size.width - 32, 40);
    [self.netModeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.netModeControl];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    NSArray *presetKeys = @[
        @"NO_SIM", @"AIRPLANE_MODE", @"CHINA_MOBILE",
        @"CHINA_UNICOM", @"CHINA_TELECOM", @"CHINA_BROADNET", @"WIFI_ONLY"
    ];
    NSString *selectedKey = presetKeys[sender.selectedSegmentIndex];
    [self applyNetworkPreset:selectedKey];
}

- (void)applyNetworkPreset:(NSString *)presetKey {
    NSString *bundleId = @"com.target.app";
    NSString *confPath = [NSString stringWithFormat:@"/var/mobile/Library/FakeDevice/Profiles/%@.plist", bundleId];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:confPath] ?: [NSMutableDictionary dictionary];

    // Load preset from network profiles
    NSString *presetPath = @"/var/mobile/Library/FakeDevice/Profiles/network_presets.json";
    NSData *presetData = [NSData dataWithContentsOfFile:presetPath];
    if (presetData) {
        NSDictionary *presets = [NSJSONSerialization JSONObjectWithData:presetData options:0 error:nil];
        NSDictionary *preset = presets[@"network_presets"][presetKey];
        if (preset) {
            [dict addEntriesFromDictionary:preset];
        }
    }

    dict[@"network_mode"] = presetKey;

    [dict writeToFile:confPath atomically:YES];
}

@end