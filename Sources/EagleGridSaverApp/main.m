#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <ScreenSaver/ScreenSaver.h>
#import "../EagleGridSaverObjC/EagleGridSaverView.h"

static NSString * const EagleDefaultsDomain = @"com.chaopi.EagleGridSaver";
static NSString * const EagleLibraryPathKey = @"EagleGridSaver.libraryPath";
static NSString * const EagleLibraryBookmarkKey = @"EagleGridSaver.libraryBookmark";
static NSString * const EagleDisplayCachePathKey = @"EagleGridSaver.displayCachePath";
static NSString * const EagleScrollSpeedMultiplierKey = @"EagleGridSaver.scrollSpeedMultiplier";
static NSString * const EagleColumnCountKey = @"EagleGridSaver.columnCount";
static NSString * const EagleDisplayCacheVersion = @"4";
static NSString * const AppleScreenSaverDomain = @"com.apple.screensaver";
static CGFloat const MinScrollSpeedMultiplier = 0.25;
static CGFloat const MaxScrollSpeedMultiplier = 10.0;
static NSInteger const MinColumnCount = 1;
static NSInteger const MaxColumnCount = 6;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSWindow *previewWindow;
@property(nonatomic, strong) EagleGridSaverView *previewView;
@property(nonatomic, strong) NSTextField *pathLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *setupLabel;
@property(nonatomic, strong) NSTextField *speedLabel;
@property(nonatomic, strong) NSSlider *speedSlider;
@property(nonatomic, strong) NSTextField *columnLabel;
@property(nonatomic, strong) NSPopUpButton *columnPopUpButton;
@property(nonatomic, strong) NSButton *updateIndexButton;
@property(nonatomic, strong) NSButton *settingsButton;
@property(nonatomic, strong) NSButton *startScreenSaverButton;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) id indexingActivity;
@property(nonatomic) IOPMAssertionID displaySleepAssertionID;
@property(nonatomic) dispatch_queue_t indexQueue;
@property(nonatomic) BOOL isPreparingIndex;
@property(nonatomic) NSUInteger lastPreparedCount;
@property(nonatomic) NSUInteger lastVideoCount;
@property(nonatomic) NSUInteger lastSkippedCount;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.indexQueue = dispatch_queue_create("com.chaopi.EagleGridSaver.indexQueue", DISPATCH_QUEUE_SERIAL);
    [self buildWindow];
    [self refreshPathLabel];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSString *)versionDisplayString {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = [info[@"CFBundleShortVersionString"] isKindOfClass:NSString.class] ? info[@"CFBundleShortVersionString"] : @"?";
    NSString *build = [info[@"CFBundleVersion"] isKindOfClass:NSString.class] ? info[@"CFBundleVersion"] : @"?";
    return [NSString stringWithFormat:@"Version %@ (%@)", version, build];
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 500)
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"Eagle Grid Saver";
    self.window.releasedWhenClosed = NO;

    NSView *content = self.window.contentView;

    NSTextField *title = [self labelWithString:@"Eagle Grid Saver" font:[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    title.frame = NSMakeRect(32, 436, 360, 36);
    [content addSubview:title];

    NSTextField *versionLabel = [self labelWithString:[self versionDisplayString] font:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    versionLabel.frame = NSMakeRect(404, 442, 184, 20);
    versionLabel.alignment = NSTextAlignmentRight;
    [content addSubview:versionLabel];

    NSTextField *description = [self labelWithString:@"Choose an Eagle .library folder. The app prepares a local display cache so the screen saver starts quickly and avoids black tiles." font:[NSFont systemFontOfSize:14 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    description.frame = NSMakeRect(32, 384, 556, 44);
    description.maximumNumberOfLines = 2;
    [content addSubview:description];

    self.setupLabel = [self labelWithString:@"Required before use: click Settings, set Use screen saver to Custom, then click Eagle Grid Saver in macOS System Settings. Until that manual selection is done, Start Screen Saver may still launch Tahoe or another Apple screen saver." font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold] color:NSColor.systemOrangeColor];
    self.setupLabel.frame = NSMakeRect(32, 314, 556, 54);
    self.setupLabel.maximumNumberOfLines = 3;
    [content addSubview:self.setupLabel];

    self.pathLabel = [self labelWithString:@"" font:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.labelColor];
    self.pathLabel.frame = NSMakeRect(32, 260, 556, 38);
    self.pathLabel.maximumNumberOfLines = 2;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:self.pathLabel];

    self.speedLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] color:NSColor.labelColor];
    self.speedLabel.frame = NSMakeRect(32, 212, 160, 20);
    [content addSubview:self.speedLabel];

    self.speedSlider = NSSlider.new;
    self.speedSlider.frame = NSMakeRect(204, 208, 384, 24);
    self.speedSlider.minValue = MinScrollSpeedMultiplier;
    self.speedSlider.maxValue = MaxScrollSpeedMultiplier;
    self.speedSlider.numberOfTickMarks = 11;
    self.speedSlider.allowsTickMarkValuesOnly = NO;
    self.speedSlider.target = self;
    self.speedSlider.action = @selector(speedChanged:);
    [content addSubview:self.speedSlider];

    self.columnLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] color:NSColor.labelColor];
    self.columnLabel.frame = NSMakeRect(32, 172, 160, 22);
    [content addSubview:self.columnLabel];

    self.columnPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(204, 168, 120, 28) pullsDown:NO];
    for (NSInteger column = MinColumnCount; column <= MaxColumnCount; column++) {
        [self.columnPopUpButton addItemWithTitle:[NSString stringWithFormat:@"%ld", (long)column]];
    }
    self.columnPopUpButton.target = self;
    self.columnPopUpButton.action = @selector(columnCountChanged:);
    [content addSubview:self.columnPopUpButton];

    NSButton *chooseButton = [NSButton buttonWithTitle:@"Choose Eagle Library..." target:self action:@selector(chooseLibrary:)];
    chooseButton.frame = NSMakeRect(32, 118, 172, 34);
    chooseButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:chooseButton];

    self.updateIndexButton = [NSButton buttonWithTitle:@"Update Index" target:self action:@selector(updateIndex:)];
    self.updateIndexButton.frame = NSMakeRect(216, 118, 116, 34);
    self.updateIndexButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:self.updateIndexButton];

    self.settingsButton = [NSButton buttonWithTitle:@"Settings" target:self action:@selector(openScreenSaverSettings:)];
    self.settingsButton.frame = NSMakeRect(344, 118, 92, 34);
    self.settingsButton.bezelStyle = NSBezelStyleRounded;
    self.settingsButton.toolTip = @"Required once: choose Eagle Grid Saver manually in macOS System Settings.";
    [content addSubview:self.settingsButton];

    self.startScreenSaverButton = [NSButton buttonWithTitle:@"Start Screen Saver" target:self action:@selector(startScreenSaver:)];
    self.startScreenSaverButton.frame = NSMakeRect(448, 118, 150, 34);
    self.startScreenSaverButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:self.startScreenSaverButton];

    self.progressIndicator = NSProgressIndicator.new;
    self.progressIndicator.frame = NSMakeRect(32, 82, 480, 16);
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.minValue = 0;
    self.progressIndicator.maxValue = 1;
    self.progressIndicator.doubleValue = 0;
    self.progressIndicator.hidden = YES;
    [content addSubview:self.progressIndicator];

    self.statusLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    self.statusLabel.frame = NSMakeRect(32, 34, 556, 34);
    self.statusLabel.maximumNumberOfLines = 2;
    [content addSubview:self.statusLabel];
    [self refreshSpeedControls];
    [self refreshColumnControls];
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = NSTextField.new;
    label.stringValue = string;
    label.font = font;
    label.textColor = color;
    label.editable = NO;
    label.selectable = YES;
    label.bordered = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    return label;
}

- (void)chooseLibrary:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"Choose Eagle Library";
    panel.prompt = @"Choose";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;
    panel.directoryURL = NSFileManager.defaultManager.homeDirectoryForCurrentUser;

    if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSURL *url = panel.URL;
    if (![url.pathExtension.lowercaseString isEqualToString:@"library"]) {
        NSAlert *alert = NSAlert.new;
        alert.messageText = @"Choose an Eagle .library folder";
        alert.informativeText = @"The selected folder does not look like an Eagle library. You can find it in Eagle: Library Settings -> Library Location.";
        [alert runModal];
        return;
    }

    NSError *error = nil;
    NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:&error];
    if (bookmark == nil) {
        NSAlert *alert = NSAlert.new;
        alert.messageText = @"Could not save folder access";
        alert.informativeText = error.localizedDescription ?: @"macOS did not return a folder access token.";
        [alert runModal];
        return;
    }

    [self saveValue:url.path bookmark:bookmark toDefaults:NSUserDefaults.standardUserDefaults];
    ScreenSaverDefaults *screenSaverDefaults = [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain];
    [self saveValue:url.path bookmark:bookmark toDefaults:screenSaverDefaults];
    CFPreferencesSetAppValue((CFStringRef)EagleLibraryPathKey, (__bridge CFStringRef)url.path, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesSetAppValue((CFStringRef)EagleLibraryBookmarkKey, (__bridge CFDataRef)bookmark, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesAppSynchronize((CFStringRef)EagleDefaultsDomain);
    [self saveCurrentHostPreferenceValue:url.path forKey:EagleLibraryPathKey];
    [self saveCurrentHostPreferenceValue:bookmark forKey:EagleLibraryBookmarkKey];
    [self saveContainerPreferenceValue:url.path forKey:EagleLibraryPathKey];
    [self saveContainerPreferenceValue:bookmark forKey:EagleLibraryBookmarkKey];

    self.statusLabel.stringValue = @"Preparing library. Please wait...";
    [self refreshPathLabel];
    [self prepareIndexForLibrary:url];
}

- (void)updateIndex:(id)sender {
    NSURL *libraryURL = [self configuredLibraryURL];
    if (libraryURL == nil) {
        self.statusLabel.stringValue = @"Choose an Eagle library first.";
        return;
    }
    [self prepareIndexForLibrary:libraryURL];
}

- (void)speedChanged:(NSSlider *)sender {
    [self saveScrollSpeedMultiplier:sender.doubleValue];
    [self refreshSpeedControls];
}

- (void)columnCountChanged:(NSPopUpButton *)sender {
    [self saveColumnCount:sender.indexOfSelectedItem + MinColumnCount];
    [self refreshColumnControls];
}

- (void)refreshSpeedControls {
    CGFloat multiplier = [self scrollSpeedMultiplier];
    self.speedLabel.stringValue = [NSString stringWithFormat:@"Scroll Speed %.1fx", multiplier];
    self.speedSlider.doubleValue = multiplier;
}

- (void)refreshColumnControls {
    NSInteger columnCount = [self columnCount];
    self.columnLabel.stringValue = [NSString stringWithFormat:@"Columns %ld", (long)columnCount];
    [self.columnPopUpButton selectItemAtIndex:columnCount - MinColumnCount];
}

- (void)openPreview:(id)sender {
    if (self.previewWindow == nil) {
        NSRect frame = NSMakeRect(0, 0, 960, 600);
        self.previewWindow = [[NSWindow alloc] initWithContentRect:frame
                                                         styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
        self.previewWindow.title = @"Eagle Grid Saver Preview";
        self.previewWindow.releasedWhenClosed = NO;
        self.previewWindow.contentMinSize = NSMakeSize(640, 400);
        self.previewView = [[EagleGridSaverView alloc] initWithFrame:self.previewWindow.contentView.bounds isPreview:YES];
        self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.previewWindow.contentView addSubview:self.previewView];
        [self.previewWindow center];
    }

    [self.previewView startAnimation];
    [self.previewWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)startScreenSaver:(id)sender {
    if (self.isPreparingIndex) {
        self.statusLabel.stringValue = @"Index is still building. Please wait before starting the screen saver.";
        return;
    }
    if (![self screenSaverPreferencesPointAtEagleGridSaver]) {
        [self showManualSelectionAlert];
        [self openScreenSaverSettings:nil];
        return;
    }

    [self restartScreenSaverHostProcesses];
    NSURL *engineURL = [NSURL fileURLWithPath:@"/System/Library/CoreServices/ScreenSaverEngine.app"];
    NSError *error = nil;
    if (![NSWorkspace.sharedWorkspace openURL:engineURL]) {
        self.statusLabel.stringValue = @"Could not start ScreenSaverEngine.";
        NSLog(@"EagleGridSaverApp: failed to open %@: %@", engineURL.path, error.localizedDescription);
    } else {
        self.statusLabel.stringValue = @"Starting screen saver. If macOS shows Tahoe or another Apple screen saver, open Settings and manually choose Eagle Grid Saver again.";
    }
}

- (BOOL)selectEagleGridSaverModule {
    NSURL *saverURL = [self installedSaverURL];
    if (saverURL == nil) {
        self.statusLabel.stringValue = @"EagleGridSaver.saver is not installed. Reinstall the package, then open this app again.";
        return NO;
    }

    NSDictionary *moduleDict = @{
        @"moduleName": @"Eagle Grid Saver",
        @"path": saverURL.path,
        @"type": @0
    };

    CFPreferencesSetAppValue(CFSTR("moduleDict"),
                             (__bridge CFPropertyListRef)moduleDict,
                             (CFStringRef)AppleScreenSaverDomain);
    CFPreferencesAppSynchronize((CFStringRef)AppleScreenSaverDomain);
    CFPreferencesSetValue(CFSTR("moduleDict"),
                          (__bridge CFPropertyListRef)moduleDict,
                          (CFStringRef)AppleScreenSaverDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesCurrentHost);
    CFPreferencesSynchronize((CFStringRef)AppleScreenSaverDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesCurrentHost);
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Eagle Grid Saver is selected. Screen saver: %@", saverURL.path];
    return YES;
}

- (BOOL)screenSaverPreferencesPointAtEagleGridSaver {
    NSDictionary *moduleDict = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("moduleDict"),
                                                                        (CFStringRef)AppleScreenSaverDomain,
                                                                        kCFPreferencesCurrentUser,
                                                                        kCFPreferencesCurrentHost));
    if (![moduleDict isKindOfClass:NSDictionary.class]) {
        moduleDict = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("moduleDict"), (CFStringRef)AppleScreenSaverDomain));
    }
    if (![moduleDict isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSString *moduleName = [moduleDict[@"moduleName"] isKindOfClass:NSString.class] ? moduleDict[@"moduleName"] : @"";
    NSString *path = [moduleDict[@"path"] isKindOfClass:NSString.class] ? moduleDict[@"path"] : @"";
    NSURL *installedSaverURL = [self installedSaverURL];
    return [moduleName isEqualToString:@"Eagle Grid Saver"] && installedSaverURL != nil && [path isEqualToString:installedSaverURL.path];
}

- (NSURL *)installedSaverURL {
    NSString *userPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Screen Savers/EagleGridSaver.saver"];
    NSString *systemPath = @"/Library/Screen Savers/EagleGridSaver.saver";
    NSArray<NSString *> *candidatePaths = @[systemPath, userPath];
    return [self installedSaverURLFromCandidatePaths:candidatePaths preferFirstExisting:YES];
}

- (NSURL *)installedSaverURLFromCandidatePaths:(NSArray<NSString *> *)candidatePaths {
    return [self installedSaverURLFromCandidatePaths:candidatePaths preferFirstExisting:NO];
}

- (NSURL *)installedSaverURLFromCandidatePaths:(NSArray<NSString *> *)candidatePaths preferFirstExisting:(BOOL)preferFirstExisting {
    NSURL *bestURL = nil;
    NSDate *bestDate = nil;
    for (NSString *path in candidatePaths) {
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
            if (preferFirstExisting) {
                return url;
            }
            NSDate *date = [self modificationDateForSaverURL:url];
            if (bestURL == nil || (date != nil && bestDate != nil && [date compare:bestDate] == NSOrderedDescending) || (date != nil && bestDate == nil)) {
                bestURL = url;
                bestDate = date;
            }
        }
    }
    return bestURL;
}

- (NSDate *)modificationDateForSaverURL:(NSURL *)saverURL {
    NSArray<NSURL *> *candidateURLs = @[
        [[saverURL URLByAppendingPathComponent:@"Contents/MacOS" isDirectory:YES] URLByAppendingPathComponent:@"EagleGridSaver"],
        saverURL
    ];
    for (NSURL *candidateURL in candidateURLs) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:candidateURL.path error:nil];
        NSDate *date = [attributes[NSFileModificationDate] isKindOfClass:NSDate.class] ? attributes[NSFileModificationDate] : nil;
        if (date != nil) {
            return date;
        }
    }
    return nil;
}

- (void)saveValue:(NSString *)path bookmark:(NSData *)bookmark toDefaults:(NSUserDefaults *)defaults {
    [defaults setObject:path forKey:EagleLibraryPathKey];
    [defaults setObject:bookmark forKey:EagleLibraryBookmarkKey];
    [defaults synchronize];
}

- (void)refreshPathLabel {
    NSString *path = [self configuredLibraryURL].path;

    if (path.length > 0) {
        self.pathLabel.stringValue = path;
        if (!self.isPreparingIndex) {
            NSDictionary *summary = [self displayCacheSummary];
            NSNumber *count = summary[@"count"];
            NSNumber *videos = summary[@"videos"];
            if (count != nil && count.unsignedIntegerValue > 0) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Ready. Index has %lu items (%lu videos). Cache: %@",
                                                (unsigned long)count.unsignedIntegerValue,
                                                (unsigned long)videos.unsignedIntegerValue,
                                                self.displayCacheFolderURL.path];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"No usable index yet. Click Update Index. Cache: %@",
                                                self.displayCacheFolderURL.path];
            }
        }
    } else {
        self.pathLabel.stringValue = @"No Eagle library selected";
        self.statusLabel.stringValue = @"Choose an Eagle library to prepare the display cache.";
    }
}

- (NSDictionary *)displayCacheSummary {
    NSURL *manifestURL = [[self displayCacheFolderURL] URLByAppendingPathComponent:@"manifest.json"];
    NSData *data = [NSData dataWithContentsOfURL:manifestURL];
    if (data == nil) {
        return @{};
    }

    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![manifest isKindOfClass:NSDictionary.class]) {
        return @{};
    }

    NSArray *items = [manifest[@"items"] isKindOfClass:NSArray.class] ? manifest[@"items"] : nil;
    NSUInteger videoCount = 0;
    for (NSDictionary *item in items) {
        if ([item isKindOfClass:NSDictionary.class] && [item[@"isVideo"] boolValue]) {
            videoCount += 1;
        }
    }

    return @{
        @"count": @(items.count),
        @"videos": @(videoCount),
        @"libraryPath": [manifest[@"libraryPath"] isKindOfClass:NSString.class] ? manifest[@"libraryPath"] : @""
    };
}

- (CGFloat)scrollSpeedMultiplier {
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain],
        [[NSUserDefaults alloc] initWithSuiteName:EagleDefaultsDomain]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        id value = [defaults objectForKey:EagleScrollSpeedMultiplierKey];
        if (value != nil) {
            return [self clampedScrollSpeedMultiplier:[value doubleValue]];
        }
    }

    id domainValue = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleScrollSpeedMultiplierKey, (CFStringRef)EagleDefaultsDomain));
    if (domainValue != nil) {
        return [self clampedScrollSpeedMultiplier:[domainValue doubleValue]];
    }

    return 1.0;
}

- (CGFloat)clampedScrollSpeedMultiplier:(CGFloat)value {
    if (!isfinite(value) || value <= 0.0) {
        return 1.0;
    }
    return MIN(MaxScrollSpeedMultiplier, MAX(MinScrollSpeedMultiplier, value));
}

- (void)saveScrollSpeedMultiplier:(CGFloat)multiplier {
    NSNumber *value = @([self clampedScrollSpeedMultiplier:multiplier]);
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain],
        [[NSUserDefaults alloc] initWithSuiteName:EagleDefaultsDomain]
    ];
    for (NSUserDefaults *defaults in defaultsList) {
        [defaults setObject:value forKey:EagleScrollSpeedMultiplierKey];
        [defaults synchronize];
    }
    CFPreferencesSetAppValue((CFStringRef)EagleScrollSpeedMultiplierKey, (__bridge CFNumberRef)value, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesAppSynchronize((CFStringRef)EagleDefaultsDomain);
    [self saveCurrentHostPreferenceValue:value forKey:EagleScrollSpeedMultiplierKey];
    [self saveContainerPreferenceValue:value forKey:EagleScrollSpeedMultiplierKey];
    [self writeRuntimeConfigWithSpeedMultiplier:value];
}

- (NSInteger)columnCount {
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain],
        [[NSUserDefaults alloc] initWithSuiteName:EagleDefaultsDomain]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        id value = [defaults objectForKey:EagleColumnCountKey];
        if (value != nil) {
            return [self clampedColumnCount:[value integerValue]];
        }
    }

    id domainValue = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleColumnCountKey, (CFStringRef)EagleDefaultsDomain));
    if (domainValue != nil) {
        return [self clampedColumnCount:[domainValue integerValue]];
    }

    return 2;
}

- (NSInteger)clampedColumnCount:(NSInteger)value {
    return MIN(MaxColumnCount, MAX(MinColumnCount, value));
}

- (void)saveColumnCount:(NSInteger)columnCount {
    NSNumber *value = @([self clampedColumnCount:columnCount]);
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain],
        [[NSUserDefaults alloc] initWithSuiteName:EagleDefaultsDomain]
    ];
    for (NSUserDefaults *defaults in defaultsList) {
        [defaults setObject:value forKey:EagleColumnCountKey];
        [defaults synchronize];
    }
    CFPreferencesSetAppValue((CFStringRef)EagleColumnCountKey, (__bridge CFNumberRef)value, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesAppSynchronize((CFStringRef)EagleDefaultsDomain);
    [self saveCurrentHostPreferenceValue:value forKey:EagleColumnCountKey];
    [self saveContainerPreferenceValue:value forKey:EagleColumnCountKey];
    [self writeRuntimeConfigWithSpeedMultiplier:@([self scrollSpeedMultiplier])];
}

- (void)saveContainerPreferenceValue:(id)value forKey:(NSString *)key {
    for (NSURL *containerRootURL in [self screenSaverContainerRootURLs]) {
        NSURL *containerPreferencesURL = [self preferencesURLForScreenSaverContainerRootURL:containerRootURL];
        NSMutableDictionary *containerPreferences = [NSMutableDictionary dictionaryWithContentsOfURL:containerPreferencesURL] ?: NSMutableDictionary.dictionary;
        containerPreferences[key] = value;
        [NSFileManager.defaultManager createDirectoryAtURL:containerPreferencesURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [containerPreferences writeToURL:containerPreferencesURL atomically:YES];
    }
}

- (void)saveCurrentHostPreferenceValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetValue((CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          (CFStringRef)EagleDefaultsDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesCurrentHost);
    CFPreferencesSynchronize((CFStringRef)EagleDefaultsDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesCurrentHost);
}

- (void)restartScreenSaverHostProcesses {
    NSArray<NSString *> *processNames = @[
        @"legacyScreenSaver",
        @"ScreenSaverEngine",
        @"WallpaperAgent",
        @"cfprefsd"
    ];
    for (NSString *processName in processNames) {
        NSTask *task = NSTask.new;
        task.launchPath = @"/usr/bin/killall";
        task.arguments = @[processName];
        task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (__unused NSException *exception) {
        }
    }
}

- (NSURL *)configuredLibraryURL {
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        NSData *bookmarkData = [self libraryBookmarkDataFromDefaults:defaults];
        NSURL *url = [self URLFromBookmarkData:bookmarkData];
        if (url != nil) {
            return url;
        }
    }

    NSData *domainBookmarkData = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleLibraryBookmarkKey, (CFStringRef)EagleDefaultsDomain));
    NSURL *domainURL = [self URLFromBookmarkData:domainBookmarkData];
    if (domainURL != nil) {
        return domainURL;
    }

    for (NSUserDefaults *defaults in defaultsList) {
        NSString *path = [defaults stringForKey:EagleLibraryPathKey];
        if (path.length > 0) {
            return [NSURL fileURLWithPath:path];
        }
    }

    NSString *domainPath = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleLibraryPathKey, (CFStringRef)EagleDefaultsDomain));
    if ([domainPath isKindOfClass:NSString.class] && domainPath.length > 0) {
        return [NSURL fileURLWithPath:domainPath];
    }

    return nil;
}

- (NSData *)configuredLibraryBookmarkData {
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain]
    ];
    for (NSUserDefaults *defaults in defaultsList) {
        NSData *bookmarkData = [self libraryBookmarkDataFromDefaults:defaults];
        if (bookmarkData.length > 0) {
            return bookmarkData;
        }
    }

    NSData *domainBookmarkData = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleLibraryBookmarkKey, (CFStringRef)EagleDefaultsDomain));
    if ([domainBookmarkData isKindOfClass:NSData.class] && domainBookmarkData.length > 0) {
        return domainBookmarkData;
    }

    return nil;
}

- (NSData *)libraryBookmarkDataFromDefaults:(NSUserDefaults *)defaults {
    id value = [defaults objectForKey:EagleLibraryBookmarkKey];
    return [value isKindOfClass:NSData.class] ? value : nil;
}

- (NSURL *)URLFromBookmarkData:(NSData *)bookmarkData {
    if (bookmarkData.length == 0) {
        return nil;
    }

    BOOL stale = NO;
    NSError *error = nil;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmarkData
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:&stale
                                             error:&error];
    if (url != nil) {
        [url startAccessingSecurityScopedResource];
        return url;
    }
    if (error != nil) {
        NSLog(@"EagleGridSaverApp: failed to resolve library bookmark: %@", error.localizedDescription);
    }
    return nil;
}

- (NSURL *)applicationSupportFolderURL {
    NSURL *supportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folderURL = [supportURL URLByAppendingPathComponent:@"EagleGridSaver" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
    return folderURL;
}

- (NSURL *)displayCacheFolderURL {
    NSURL *folderURL = [[self applicationSupportFolderURL] URLByAppendingPathComponent:@"DisplayCache" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
    return folderURL;
}

- (NSURL *)runtimeConfigURLForDisplayCacheFolderURL:(NSURL *)cacheURL {
    return [cacheURL URLByAppendingPathComponent:@"runtime-config.json"];
}

- (void)writeRuntimeConfigWithSpeedMultiplier:(NSNumber *)speedMultiplier {
    NSNumber *columnCount = @([self columnCount]);
    NSDictionary *config = @{
        @"version": @1,
        EagleScrollSpeedMultiplierKey: @([self clampedScrollSpeedMultiplier:speedMultiplier.doubleValue]),
        @"scrollSpeedMultiplier": @([self clampedScrollSpeedMultiplier:speedMultiplier.doubleValue]),
        EagleColumnCountKey: columnCount,
        @"columnCount": columnCount,
        @"updatedAt": @((NSInteger)NSDate.date.timeIntervalSince1970)
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:config options:0 error:nil];
    if (data == nil) {
        return;
    }

    NSMutableArray<NSURL *> *cacheFolders = NSMutableArray.array;
    [cacheFolders addObject:[self displayCacheFolderURL]];
    for (NSURL *containerRootURL in [self screenSaverContainerRootURLs]) {
        [cacheFolders addObject:[self displayCacheFolderURLForScreenSaverContainerRootURL:containerRootURL]];
    }

    for (NSURL *cacheURL in cacheFolders) {
        [NSFileManager.defaultManager createDirectoryAtURL:cacheURL withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:[self runtimeConfigURLForDisplayCacheFolderURL:cacheURL] atomically:YES];
    }
}

- (NSArray<NSURL *> *)screenSaverContainerRootURLs {
    NSURL *homeURL = NSFileManager.defaultManager.homeDirectoryForCurrentUser;
    NSURL *containersURL = [homeURL URLByAppendingPathComponent:@"Library/Containers" isDirectory:YES];
    NSArray<NSString *> *knownContainerNames = @[
        @"com.apple.ScreenSaver-Settings.extension",
        @"com.apple.settings-intents.ScreenSaverIntents",
        @"com.apple.ScreenSaver.Engine.legacyScreenSaver",
        @"com.apple.ScreenSaver.Engine.legacyScreenSaver.x86-64",
        @"com.apple.ScreenSaver.Engine"
    ];

    NSMutableArray<NSURL *> *roots = NSMutableArray.array;
    NSMutableSet<NSString *> *seen = NSMutableSet.set;
    void (^addRoot)(NSURL *) = ^(NSURL *rootURL) {
        if (rootURL.path.length == 0 || [seen containsObject:rootURL.path]) {
            return;
        }
        [seen addObject:rootURL.path];
        [roots addObject:rootURL];
    };

    for (NSString *name in knownContainerNames) {
        addRoot([containersURL URLByAppendingPathComponent:name isDirectory:YES]);
    }

    NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:containersURL includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for (NSURL *child in children) {
        NSString *name = child.lastPathComponent;
        if ([name hasPrefix:@"com.apple.ScreenSaver.Engine"] ||
            [name isEqualToString:@"com.apple.ScreenSaver-Settings.extension"] ||
            [name isEqualToString:@"com.apple.settings-intents.ScreenSaverIntents"] ||
            [name containsString:@"legacyScreenSaver"]) {
            addRoot(child);
        }
    }

    return roots;
}

- (NSURL *)displayCacheFolderURLForScreenSaverContainerRootURL:(NSURL *)containerRootURL {
    NSURL *folderURL = [containerRootURL URLByAppendingPathComponent:@"Data/Library/Application Support/EagleGridSaver/DisplayCache" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
    return folderURL;
}

- (NSURL *)preferencesURLForScreenSaverContainerRootURL:(NSURL *)containerRootURL {
    return [containerRootURL URLByAppendingPathComponent:@"Data/Library/Preferences/com.chaopi.EagleGridSaver.plist"];
}

- (void)clearStaleScreenSaverStateForContainerRootURL:(NSURL *)containerRootURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *supportURL = [containerRootURL URLByAppendingPathComponent:@"Data/Library/Application Support/EagleGridSaver" isDirectory:YES];
    [fileManager removeItemAtURL:supportURL error:nil];

    NSURL *preferencesURL = [self preferencesURLForScreenSaverContainerRootURL:containerRootURL];
    [fileManager removeItemAtURL:preferencesURL error:nil];

    NSURL *byHostURL = [containerRootURL URLByAppendingPathComponent:@"Data/Library/Preferences/ByHost" isDirectory:YES];
    NSArray<NSURL *> *preferenceFiles = [fileManager contentsOfDirectoryAtURL:byHostURL
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:nil];
    for (NSURL *preferenceURL in preferenceFiles) {
        NSString *name = preferenceURL.lastPathComponent;
        if ([name hasPrefix:@"com.chaopi.EagleGridSaver."] ||
            [name hasPrefix:@"com.chaopi.EagleGridSaverApp."]) {
            [fileManager removeItemAtURL:preferenceURL error:nil];
        }
    }
}

- (void)prepareIndexForLibrary:(NSURL *)libraryURL {
    if (self.isPreparingIndex) {
        return;
    }

    self.isPreparingIndex = YES;
    self.indexingActivity = [NSProcessInfo.processInfo beginActivityWithOptions:(NSActivityUserInitiated | NSActivityIdleDisplaySleepDisabled)
                                                                         reason:@"Eagle Grid Saver is building its display index"];
    self.displaySleepAssertionID = kIOPMNullAssertionID;
    IOReturn assertionResult = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                                           kIOPMAssertionLevelOn,
                                                           CFSTR("Eagle Grid Saver is building its display index"),
                                                           &_displaySleepAssertionID);
    if (assertionResult != kIOReturnSuccess) {
        NSLog(@"EagleGridSaverApp: failed to prevent idle display sleep while indexing: %d", assertionResult);
    }
    self.updateIndexButton.enabled = NO;
    self.settingsButton.enabled = NO;
    self.startScreenSaverButton.enabled = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0;
    self.statusLabel.stringValue = @"Building index. Please wait...";
    [self restartScreenSaverHostProcesses];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.indexQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        BOOL prepared = [strongSelf buildDisplayCacheForLibrary:libraryURL];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }
            innerSelf.isPreparingIndex = NO;
            innerSelf.updateIndexButton.enabled = YES;
            innerSelf.settingsButton.enabled = YES;
            innerSelf.startScreenSaverButton.enabled = YES;
            if (innerSelf.indexingActivity != nil) {
                [NSProcessInfo.processInfo endActivity:innerSelf.indexingActivity];
                innerSelf.indexingActivity = nil;
            }
            if (innerSelf.displaySleepAssertionID != kIOPMNullAssertionID) {
                IOPMAssertionRelease(innerSelf.displaySleepAssertionID);
                innerSelf.displaySleepAssertionID = kIOPMNullAssertionID;
            }
            if (prepared) {
                innerSelf.progressIndicator.doubleValue = 1;
            }
            innerSelf.progressIndicator.hidden = YES;
        });
    });
}

- (BOOL)buildDisplayCacheForLibrary:(NSURL *)libraryURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *imagesURL = [libraryURL URLByAppendingPathComponent:@"images" isDirectory:YES];
    NSURL *cacheURL = [self displayCacheFolderURL];
    NSMutableArray<NSURL *> *mediaFiles = NSMutableArray.array;
    NSSet<NSString *> *imageExtensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"webp", @"heic", @"tif", @"tiff", @"gif"]];
    NSSet<NSString *> *videoExtensions = [NSSet setWithArray:@[@"mov", @"mp4", @"m4v"]];

    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:imagesURL.path isDirectory:&isDirectory] || !isDirectory) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.stringValue = @"Could not read the Eagle library images folder. Choose the library again and grant access if macOS asks.";
            self.progressIndicator.doubleValue = 0;
            self.progressIndicator.hidden = YES;
        });
        return NO;
    }

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:imagesURL includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url, NSError *error) {
        NSLog(@"EagleGridSaverApp: cache scan error %@: %@", url.path, error.localizedDescription);
        return YES;
    }];

    for (NSURL *fileURL in enumerator) {
        NSString *extension = fileURL.pathExtension.lowercaseString;
        BOOL isVideo = [videoExtensions containsObject:extension];
        if (![imageExtensions containsObject:extension] && !isVideo) {
            continue;
        }
        if ([fileURL.URLByDeletingPathExtension.lastPathComponent hasSuffix:@"_thumbnail"]) {
            continue;
        }
        if (![fileURL.URLByDeletingLastPathComponent.lastPathComponent hasSuffix:@".info"]) {
            continue;
        }
        [mediaFiles addObject:fileURL];
    }

    NSMutableArray<NSDictionary *> *items = NSMutableArray.array;
    NSUInteger total = MAX((NSUInteger)1, mediaFiles.count);
    __block NSUInteger processed = 0;
    __block NSUInteger succeeded = 0;
    __block NSUInteger failed = 0;
    __block NSUInteger videoSucceeded = 0;

    if (mediaFiles.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.stringValue = @"No supported Eagle assets found in this library.";
            self.progressIndicator.doubleValue = 0;
            self.progressIndicator.hidden = YES;
        });
        return NO;
    }

    NSData *libraryBookmark = [self configuredLibraryBookmarkData];
    NSNumber *speedMultiplier = @([self scrollSpeedMultiplier]);
    NSNumber *columnCount = @([self columnCount]);
    [self persistRuntimeSelectionForLibraryURL:libraryURL
                                libraryBookmark:libraryBookmark
                                      cacheURL:cacheURL
                               speedMultiplier:speedMultiplier
                                   columnCount:columnCount];

    for (NSURL *fileURL in mediaFiles) {
        @autoreleasepool {
            NSString *extension = fileURL.pathExtension.lowercaseString;
            BOOL isVideo = [videoExtensions containsObject:extension];
            NSDictionary *metadata = [self metadataForInfoFolder:fileURL.URLByDeletingLastPathComponent];
            if ([metadata[@"isDeleted"] boolValue]) {
                processed += 1;
                continue;
            }

            NSString *cacheName = [self cacheFilenameForSourceURL:fileURL];
            NSURL *outputURL = [cacheURL URLByAppendingPathComponent:cacheName];
            CGSize outputSize = CGSizeZero;
            BOOL ok = NO;

            if ([fileManager fileExistsAtPath:outputURL.path]) {
                outputSize = [self imageSizeForURL:outputURL];
                ok = outputSize.width > 0 && outputSize.height > 0;
            }

            if (!ok) {
                ok = [self writeDisplayImageForSourceURL:fileURL isVideo:isVideo toURL:outputURL outputSize:&outputSize];
            }

            if (ok) {
                succeeded += 1;
                if (isVideo) {
                    videoSucceeded += 1;
                }
                NSString *title = [metadata[@"name"] isKindOfClass:NSString.class] ? metadata[@"name"] : fileURL.URLByDeletingPathExtension.lastPathComponent;
                [items addObject:@{
                    @"cachePath": cacheName,
                    @"sourcePath": fileURL.path ?: @"",
                    @"title": title ?: @"",
                    @"width": @(MAX(1.0, outputSize.width)),
                    @"height": @(MAX(1.0, outputSize.height)),
                    @"isVideo": @(isVideo)
                }];
            } else {
                failed += 1;
            }

            processed += 1;
            if (processed % 10 == 0 || processed == mediaFiles.count) {
                double progress = MIN(1.0, (double)processed / (double)total);
                NSString *status = [NSString stringWithFormat:@"Building index. Please wait... %lu / %lu, prepared %lu, skipped %lu",
                                    (unsigned long)processed,
                                    (unsigned long)mediaFiles.count,
                                    (unsigned long)succeeded,
                                    (unsigned long)failed];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressIndicator.doubleValue = progress;
                    self.statusLabel.stringValue = status;
                });
            }
        }
    }

    [self removeStaleCacheFilesInFolder:cacheURL keepingItems:items];

    NSDictionary *manifest = @{
        @"version": EagleDisplayCacheVersion,
        @"libraryPath": libraryURL.path ?: @"",
        @"generatedAt": @((NSInteger)NSDate.date.timeIntervalSince1970),
        @"scrollSpeedMultiplier": speedMultiplier,
        @"columnCount": columnCount,
        @"items": items
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil];
    NSURL *manifestURL = [cacheURL URLByAppendingPathComponent:@"manifest.json"];
    BOOL wroteManifest = [data writeToURL:manifestURL atomically:YES];
    if (!wroteManifest) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Index build failed. Could not write manifest: %@",
                                            manifestURL.path];
        });
        return NO;
    }
    [self writeRuntimeConfigWithSpeedMultiplier:speedMultiplier];

    NSUInteger mirroredContainerCount = 0;
    for (NSURL *containerRootURL in [self screenSaverContainerRootURLs]) {
        NSURL *containerPreferencesURL = [self preferencesURLForScreenSaverContainerRootURL:containerRootURL];
        NSDictionary *oldContainerPreferences = [NSDictionary dictionaryWithContentsOfURL:containerPreferencesURL];
        NSData *containerLibraryBookmark = [oldContainerPreferences[EagleLibraryBookmarkKey] isKindOfClass:NSData.class] ? oldContainerPreferences[EagleLibraryBookmarkKey] : libraryBookmark;
        [self clearStaleScreenSaverStateForContainerRootURL:containerRootURL];
        NSURL *containerCacheURL = [self displayCacheFolderURLForScreenSaverContainerRootURL:containerRootURL];
        BOOL mirrored = [self mirrorDisplayCacheFromFolder:cacheURL toFolder:containerCacheURL keepingItems:items];
        if (mirrored) {
            mirroredContainerCount += 1;
        }
        NSMutableDictionary *containerPreferences = [NSMutableDictionary dictionaryWithContentsOfURL:containerPreferencesURL] ?: NSMutableDictionary.dictionary;
        containerPreferences[EagleLibraryPathKey] = libraryURL.path ?: @"";
        containerPreferences[EagleDisplayCachePathKey] = mirrored ? (containerCacheURL.path ?: @"") : (cacheURL.path ?: @"");
        containerPreferences[EagleScrollSpeedMultiplierKey] = speedMultiplier;
        containerPreferences[EagleColumnCountKey] = columnCount;
        if (containerLibraryBookmark.length > 0) {
            containerPreferences[EagleLibraryBookmarkKey] = containerLibraryBookmark;
        }
        [NSFileManager.defaultManager createDirectoryAtURL:containerPreferencesURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [containerPreferences writeToURL:containerPreferencesURL atomically:YES];
    }

    self.lastPreparedCount = succeeded;
    self.lastVideoCount = videoSucceeded;
    self.lastSkippedCount = failed;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Ready. Index has %lu items (%lu videos), skipped %lu. Cache: %@ (synced %lu screen saver container%@)",
                                        (unsigned long)succeeded,
                                        (unsigned long)videoSucceeded,
                                        (unsigned long)failed,
                                        cacheURL.path,
                                        (unsigned long)mirroredContainerCount,
                                        mirroredContainerCount == 1 ? @"" : @"s"];
    });
    return succeeded > 0;
}

- (void)persistRuntimeSelectionForLibraryURL:(NSURL *)libraryURL
                            libraryBookmark:(NSData *)libraryBookmark
                                    cacheURL:(NSURL *)cacheURL
                             speedMultiplier:(NSNumber *)speedMultiplier
                                 columnCount:(NSNumber *)columnCount {
    NSUserDefaults *standardDefaults = NSUserDefaults.standardUserDefaults;
    [standardDefaults setObject:libraryURL.path ?: @"" forKey:EagleLibraryPathKey];
    [standardDefaults setObject:cacheURL.path ?: @"" forKey:EagleDisplayCachePathKey];
    [standardDefaults setObject:speedMultiplier forKey:EagleScrollSpeedMultiplierKey];
    [standardDefaults setObject:columnCount forKey:EagleColumnCountKey];
    if (libraryBookmark.length > 0) {
        [standardDefaults setObject:libraryBookmark forKey:EagleLibraryBookmarkKey];
    }
    [standardDefaults synchronize];

    ScreenSaverDefaults *screenSaverDefaults = [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain];
    [screenSaverDefaults setObject:libraryURL.path ?: @"" forKey:EagleLibraryPathKey];
    [screenSaverDefaults setObject:cacheURL.path ?: @"" forKey:EagleDisplayCachePathKey];
    [screenSaverDefaults setObject:speedMultiplier forKey:EagleScrollSpeedMultiplierKey];
    [screenSaverDefaults setObject:columnCount forKey:EagleColumnCountKey];
    if (libraryBookmark.length > 0) {
        [screenSaverDefaults setObject:libraryBookmark forKey:EagleLibraryBookmarkKey];
    }
    [screenSaverDefaults synchronize];

    CFPreferencesSetAppValue((CFStringRef)EagleLibraryPathKey, (__bridge CFStringRef)(libraryURL.path ?: @""), (CFStringRef)EagleDefaultsDomain);
    CFPreferencesSetAppValue((CFStringRef)EagleDisplayCachePathKey, (__bridge CFStringRef)(cacheURL.path ?: @""), (CFStringRef)EagleDefaultsDomain);
    CFPreferencesSetAppValue((CFStringRef)EagleScrollSpeedMultiplierKey, (__bridge CFNumberRef)speedMultiplier, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesSetAppValue((CFStringRef)EagleColumnCountKey, (__bridge CFNumberRef)columnCount, (CFStringRef)EagleDefaultsDomain);
    if (libraryBookmark.length > 0) {
        CFPreferencesSetAppValue((CFStringRef)EagleLibraryBookmarkKey, (__bridge CFDataRef)libraryBookmark, (CFStringRef)EagleDefaultsDomain);
    }
    CFPreferencesAppSynchronize((CFStringRef)EagleDefaultsDomain);

    [self saveCurrentHostPreferenceValue:libraryURL.path ?: @"" forKey:EagleLibraryPathKey];
    [self saveCurrentHostPreferenceValue:cacheURL.path ?: @"" forKey:EagleDisplayCachePathKey];
    [self saveCurrentHostPreferenceValue:speedMultiplier forKey:EagleScrollSpeedMultiplierKey];
    [self saveCurrentHostPreferenceValue:columnCount forKey:EagleColumnCountKey];
    if (libraryBookmark.length > 0) {
        [self saveCurrentHostPreferenceValue:libraryBookmark forKey:EagleLibraryBookmarkKey];
    }

    [self saveContainerPreferenceValue:libraryURL.path ?: @"" forKey:EagleLibraryPathKey];
    [self saveContainerPreferenceValue:cacheURL.path ?: @"" forKey:EagleDisplayCachePathKey];
    [self saveContainerPreferenceValue:speedMultiplier forKey:EagleScrollSpeedMultiplierKey];
    [self saveContainerPreferenceValue:columnCount forKey:EagleColumnCountKey];
    if (libraryBookmark.length > 0) {
        [self saveContainerPreferenceValue:libraryBookmark forKey:EagleLibraryBookmarkKey];
    }
}

- (BOOL)mirrorDisplayCacheFromFolder:(NSURL *)sourceFolderURL toFolder:(NSURL *)targetFolderURL keepingItems:(NSArray<NSDictionary *> *)items {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager createDirectoryAtURL:targetFolderURL withIntermediateDirectories:YES attributes:nil error:nil]) {
        return NO;
    }

    [self removeStaleCacheFilesInFolder:targetFolderURL keepingItems:items];

    NSMutableArray<NSString *> *names = NSMutableArray.array;
    [names addObject:@"manifest.json"];
    [names addObject:@"runtime-config.json"];
    for (NSDictionary *item in items) {
        NSString *cachePath = [item[@"cachePath"] isKindOfClass:NSString.class] ? item[@"cachePath"] : nil;
        if (cachePath.length > 0) {
            [names addObject:cachePath.lastPathComponent];
        }
    }

    BOOL allOK = YES;
    for (NSString *name in names) {
        NSURL *sourceURL = [sourceFolderURL URLByAppendingPathComponent:name];
        NSURL *targetURL = [targetFolderURL URLByAppendingPathComponent:name];
        if (![fileManager fileExistsAtPath:sourceURL.path]) {
            allOK = NO;
            continue;
        }

        [fileManager removeItemAtURL:targetURL error:nil];
        NSError *linkError = nil;
        if ([fileManager linkItemAtURL:sourceURL toURL:targetURL error:&linkError]) {
            continue;
        }

        NSError *copyError = nil;
        if (![fileManager copyItemAtURL:sourceURL toURL:targetURL error:&copyError]) {
            NSLog(@"EagleGridSaverApp: failed to mirror cache file %@: link=%@ copy=%@",
                  name,
                  linkError.localizedDescription,
                  copyError.localizedDescription);
            allOK = NO;
        }
    }

    return allOK;
}

- (void)removeStaleCacheFilesInFolder:(NSURL *)cacheURL keepingItems:(NSArray<NSDictionary *> *)items {
    NSMutableSet<NSString *> *keepNames = NSMutableSet.set;
    [keepNames addObject:@"manifest.json"];
    [keepNames addObject:@"runtime-config.json"];
    for (NSDictionary *item in items) {
        NSString *cachePath = [item[@"cachePath"] isKindOfClass:NSString.class] ? item[@"cachePath"] : nil;
        if (cachePath.length > 0) {
            [keepNames addObject:cachePath.lastPathComponent];
        }
    }

    NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:cacheURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for (NSURL *child in children) {
        if (![keepNames containsObject:child.lastPathComponent]) {
            [NSFileManager.defaultManager removeItemAtURL:child error:nil];
        }
    }
}

- (NSDictionary *)metadataForInfoFolder:(NSURL *)infoURL {
    NSData *data = [NSData dataWithContentsOfURL:[infoURL URLByAppendingPathComponent:@"metadata.json"]];
    if (data == nil) {
        return @{};
    }
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [metadata isKindOfClass:NSDictionary.class] ? metadata : @{};
}

- (NSString *)cacheFilenameForSourceURL:(NSURL *)sourceURL {
    NSString *key = sourceURL.path;
    NSUInteger hash = key.hash;
    NSString *base = sourceURL.URLByDeletingPathExtension.lastPathComponent;
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    NSMutableString *safe = NSMutableString.string;
    for (NSUInteger index = 0; index < MIN((NSUInteger)36, base.length); index++) {
        unichar ch = [base characterAtIndex:index];
        [safe appendString:[allowed characterIsMember:ch] ? [NSString stringWithCharacters:&ch length:1] : @"-"];
    }
    if (safe.length == 0) {
        [safe appendString:@"asset"];
    }
    return [NSString stringWithFormat:@"%@-%lu-%@.jpg", EagleDisplayCacheVersion, (unsigned long)hash, safe];
}

- (BOOL)writeDisplayImageForSourceURL:(NSURL *)sourceURL isVideo:(BOOL)isVideo toURL:(NSURL *)outputURL outputSize:(CGSize *)outputSize {
    CGImageRef imageRef = NULL;
    if (isVideo) {
        imageRef = [self posterImageRefForVideoURL:sourceURL];
        if (imageRef == NULL) {
            NSURL *thumbnailURL = [self thumbnailURLForSourceURL:sourceURL];
            if (thumbnailURL != nil) {
                imageRef = [self thumbnailImageRefForImageURL:thumbnailURL maxPixelSize:1800];
            }
        }
    } else {
        imageRef = [self thumbnailImageRefForImageURL:sourceURL maxPixelSize:1800];
        if (imageRef == NULL) {
            NSURL *thumbnailURL = [self thumbnailURLForSourceURL:sourceURL];
            if (thumbnailURL != nil) {
                imageRef = [self thumbnailImageRefForImageURL:thumbnailURL maxPixelSize:1800];
            }
        }
    }

    if (imageRef == NULL) {
        return NO;
    }

    BOOL written = [self writeJPEGImageRef:imageRef toURL:outputURL];
    if (written && outputSize != NULL) {
        *outputSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    }
    CGImageRelease(imageRef);
    return written;
}

- (CGImageRef)thumbnailImageRefForImageURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return NULL;
    }
    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageIfAbsent: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize)
    };
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    return imageRef;
}

- (CGImageRef)posterImageRefForVideoURL:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(1800, 1800);

    Float64 duration = CMTimeGetSeconds(asset.duration);
    NSMutableArray<NSNumber *> *seconds = NSMutableArray.array;
    if (isfinite(duration) && duration > 0.2) {
        [seconds addObject:@(MIN(MAX(duration * 0.10, 0.25), MAX(0.0, duration - 0.05)))];
        [seconds addObject:@(MIN(MAX(duration * 0.25, 0.5), MAX(0.0, duration - 0.05)))];
        [seconds addObject:@(MIN(MAX(duration * 0.50, 0.75), MAX(0.0, duration - 0.05)))];
        [seconds addObject:@(MIN(MAX(duration * 0.75, 1.0), MAX(0.0, duration - 0.05)))];
    }
    [seconds addObject:@1.0];
    [seconds addObject:@0.25];
    [seconds addObject:@0.0];

    CGImageRef fallbackRef = NULL;
    CGFloat fallbackBrightness = -1.0;
    for (NSNumber *second in seconds) {
        CMTime time = [second doubleValue] <= 0.0 ? kCMTimeZero : CMTimeMakeWithSeconds([second doubleValue], 600);
        CGImageRef candidateRef = [generator copyCGImageAtTime:time actualTime:NULL error:nil];
        if (candidateRef == NULL) {
            continue;
        }

        CGFloat brightness = [self averageBrightnessForImageRef:candidateRef];
        if (brightness > fallbackBrightness) {
            if (fallbackRef != NULL) {
                CGImageRelease(fallbackRef);
            }
            fallbackRef = candidateRef;
            fallbackBrightness = brightness;
        } else {
            CGImageRelease(candidateRef);
        }

        if (brightness >= 0.08) {
            return fallbackRef;
        }
    }
    return fallbackRef;
}

- (CGFloat)averageBrightnessForImageRef:(CGImageRef)imageRef {
    if (imageRef == NULL) {
        return 0.0;
    }

    static const size_t width = 16;
    static const size_t height = 16;
    uint8_t pixels[width * height * 4];
    memset(pixels, 0, sizeof(pixels));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels,
                                                 width,
                                                 height,
                                                 8,
                                                 width * 4,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        return 0.0;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);

    double total = 0.0;
    for (size_t index = 0; index < width * height; index++) {
        uint8_t *pixel = pixels + index * 4;
        total += (0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]) / 255.0;
    }
    return (CGFloat)(total / (double)(width * height));
}

- (NSURL *)thumbnailURLForSourceURL:(NSURL *)sourceURL {
    NSURL *folderURL = sourceURL.URLByDeletingLastPathComponent;
    NSString *base = sourceURL.URLByDeletingPathExtension.lastPathComponent;
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    for (NSString *extension in extensions) {
        NSURL *candidate = [folderURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@_thumbnail.%@", base, extension]];
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
            return candidate;
        }
    }
    return nil;
}

- (BOOL)writeJPEGImageRef:(CGImageRef)imageRef toURL:(NSURL *)url {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    if (destination == NULL) {
        return NO;
    }
    NSDictionary *properties = @{
        (NSString *)kCGImageDestinationLossyCompressionQuality: @(0.86)
    };
    CGImageDestinationAddImage(destination, imageRef, (__bridge CFDictionaryRef)properties);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return ok;
}

- (CGSize)imageSizeForURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return CGSizeZero;
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return CGSizeMake([properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue],
                      [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue]);
}

- (void)openScreenSaverSettings:(id)sender {
    [self selectEagleGridSaverModule];
    if (sender != nil) {
        [self showManualSelectionAlert];
    }
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)showManualSelectionAlert {
    NSAlert *alert = NSAlert.new;
    alert.messageText = @"Choose Eagle Grid Saver in macOS Settings";
    alert.informativeText = @"macOS does not let this app silently replace the selected system screen saver. In System Settings, set Use screen saver to Custom and click Eagle Grid Saver once. Until you do this, Start Screen Saver may still launch Tahoe or another Apple screen saver. After this manual step, speed, columns, and index rebuilds work from this app.";
    [alert addButtonWithTitle:@"Open Settings"];
    [alert runModal];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "--build-index") == 0) {
            AppDelegate *delegate = AppDelegate.new;
            delegate.indexQueue = dispatch_queue_create("com.chaopi.EagleGridSaver.indexQueue.cli", DISPATCH_QUEUE_SERIAL);
            NSURL *libraryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
            BOOL ok = [delegate buildDisplayCacheForLibrary:libraryURL];
            return ok ? 0 : 1;
        }
        if (argc == 2 && strcmp(argv[1], "--select-saver") == 0) {
            AppDelegate *delegate = AppDelegate.new;
            return [delegate selectEagleGridSaverModule] ? 0 : 1;
        }
        if (argc > 2 && strcmp(argv[1], "--preferred-saver-path") == 0) {
            NSMutableArray<NSString *> *paths = NSMutableArray.array;
            for (int index = 2; index < argc; index++) {
                [paths addObject:[NSString stringWithUTF8String:argv[index]]];
            }
            AppDelegate *delegate = AppDelegate.new;
            NSURL *url = [delegate installedSaverURLFromCandidatePaths:paths];
            if (url == nil) {
                return 1;
            }
            printf("%s\n", url.path.UTF8String);
            return 0;
        }

        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = AppDelegate.new;
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
