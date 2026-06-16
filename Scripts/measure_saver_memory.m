#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <mach/mach.h>

static uint64_t ResidentBytes(void) {
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? info.resident_size : 0;
}

static uint64_t FootprintBytes(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? info.phys_footprint : 0;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: measure_saver_memory <saver-path> [frames]\n");
            return 2;
        }

        NSString *saverPath = [NSString stringWithUTF8String:argv[1]];
        NSInteger frameCount = argc >= 3 ? [[NSString stringWithUTF8String:argv[2]] integerValue] : 2000;
        NSBundle *bundle = [NSBundle bundleWithPath:saverPath];
        if (bundle == nil || ![bundle load]) {
            fprintf(stderr, "failed to load saver bundle: %s\n", saverPath.UTF8String);
            return 1;
        }

        Class principalClass = bundle.principalClass;
        ScreenSaverView *view = [[principalClass alloc] initWithFrame:NSMakeRect(0, 0, 1440, 900) isPreview:NO];
        if (view == nil) {
            fprintf(stderr, "failed to create saver view\n");
            return 1;
        }

        [view startAnimation];
        [view drawRect:view.bounds];

        uint64_t maxResident = ResidentBytes();
        uint64_t maxFootprint = FootprintBytes();
        for (NSInteger i = 0; i < frameCount; i++) {
            @autoreleasepool {
                [view animateOneFrame];
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
            }
            maxResident = MAX(maxResident, ResidentBytes());
            maxFootprint = MAX(maxFootprint, FootprintBytes());
        }

        NSArray *cells = [view valueForKey:@"cells"];
        NSUInteger activeVideoPlayers = 0;
        for (id cell in cells) {
            if ([cell valueForKey:@"player"] != nil) {
                activeVideoPlayers += 1;
            }
        }

        printf("frames=%ld\n", (long)frameCount);
        printf("cells=%lu\n", (unsigned long)cells.count);
        printf("activeVideoPlayers=%lu\n", (unsigned long)activeVideoPlayers);
        printf("maxResidentBytes=%llu\n", maxResident);
        printf("maxResidentMB=%.1f\n", (double)maxResident / 1024.0 / 1024.0);
        printf("maxFootprintBytes=%llu\n", maxFootprint);
        printf("maxFootprintMB=%.1f\n", (double)maxFootprint / 1024.0 / 1024.0);

        [view stopAnimation];
        printf("afterStopResidentMB=%.1f\n", (double)ResidentBytes() / 1024.0 / 1024.0);
        printf("afterStopFootprintMB=%.1f\n", (double)FootprintBytes() / 1024.0 / 1024.0);
    }
    return 0;
}
