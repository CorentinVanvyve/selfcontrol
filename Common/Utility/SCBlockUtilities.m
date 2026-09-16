//
//  SCBlockUtilities.m
//  SelfControl
//
//  Created by Charlie Stigler on 1/19/21.
//

#import "SCBlockUtilities.h"
#import "HostFileBlocker.h"
#import "PacketFilter.h"

@implementation SCBlockUtilities

+ (BOOL)anyBlockIsRunning {
    BOOL blockIsRunning = [SCBlockUtilities modernBlockIsRunning] || [SCBlockUtilities legacyBlockIsRunning];

    return blockIsRunning;
}

+ (BOOL)modernBlockIsRunning {
    SCSettings* settings = [SCSettings sharedSettings];
    
    return [settings boolForKey: @"BlockIsRunning"];
}

+ (BOOL)legacyBlockIsRunning {
    // first see if there's a legacy settings file from v3.x
    // which could be in any user's home folder
    NSError* homeDirErr = nil;
    NSArray<NSURL *>* homeDirectoryURLs = [SCMiscUtilities allUserHomeDirectoryURLs: &homeDirErr];
    if (homeDirectoryURLs != nil) {
        for (NSURL* homeDirURL in homeDirectoryURLs) {
            NSString* relativeSettingsPath = [NSString stringWithFormat: @"/Library/Preferences/%@", SCSettings.settingsFileName];
            NSURL* settingsFileURL = [homeDirURL URLByAppendingPathComponent: relativeSettingsPath isDirectory: NO];
            
            if ([SCMigrationUtilities legacyBlockIsRunningInSettingsFile: settingsFileURL]) {
                return YES;
            }
        }
    }

    // nope? OK, how about a lock file from pre-3.0?
    if ([SCMigrationUtilities legacyLockFileExists]) {
        return YES;
    }
    
    // we don't check defaults anymore, though pre-3.0 blocks did
    // have data stored there. That should be covered by the lockfile anyway
    
    return NO;
}

// returns YES if the block should have expired active based on the specified end time (i.e. the end time is in the past), or NO otherwise
+ (BOOL)currentBlockIsExpired {
    // the block should be running if the end date hasn't arrived yet
    SCSettings* settings = [SCSettings sharedSettings];
    if ([[settings valueForKey: @"BlockEndDate"] timeIntervalSinceNow] > 0) {
        return NO;
    } else {
        return YES;
    }
}

+ (BOOL)blockRulesFoundOnSystem {
    return [PacketFilter blockFoundInPF] || [HostFileBlocker blockFoundInHostsFile];
}

+ (void) removeBlockFromSettings {
    SCSettings* settings = [SCSettings sharedSettings];
    [settings setValue: @NO forKey: @"BlockIsRunning"];
    [settings setValue: nil forKey: @"BlockEndDate"];
    [settings setValue: nil forKey: @"ActiveBlocklist"];
    [settings setValue: nil forKey: @"ActiveBlockAsWhitelist"];
}

+ (NSInteger)freeWindowStartHour {
    SCSettings* settings = [SCSettings sharedSettings];
    id value = [settings valueForKey: @"FreeWindowStartHour"];
    return value != nil ? [value integerValue] : 17;
}

+ (NSInteger)freeWindowEndHour {
    SCSettings* settings = [SCSettings sharedSettings];
    id value = [settings valueForKey: @"FreeWindowEndHour"];
    return value != nil ? [value integerValue] : 18;
}

+ (NSInteger)freeWindowDurationHoursFromStart:(NSInteger)startHour end:(NSInteger)endHour {
    return ((endHour - startHour) + 24) % 24;
}

+ (BOOL)isHour:(NSInteger)hour inWindowFromStart:(NSInteger)startHour end:(NSInteger)endHour {
    if (startHour == endHour) {
        // degenerate window - treat as "never" rather than "always" (safer default: no free window)
        return NO;
    }
    if (startHour < endHour) {
        return hour >= startHour && hour < endHour;
    }
    // wraps midnight, e.g. start=22 end=2
    return hour >= startHour || hour < endHour;
}

+ (BOOL)isInScheduledBlockWindow {
    NSCalendar* cal = [NSCalendar currentCalendar];
    NSInteger hour = [cal component: NSCalendarUnitHour fromDate: [NSDate date]];

    BOOL inFreeWindow = [SCBlockUtilities isHour: hour
                                inWindowFromStart: [SCBlockUtilities freeWindowStartHour]
                                              end: [SCBlockUtilities freeWindowEndHour]];
    return !inFreeWindow;
}

+ (NSDate*)nextScheduledBlockEndDate {
    NSCalendar* cal = [NSCalendar currentCalendar];
    NSDate* now = [NSDate date];
    NSInteger freeWindowStartHour = [SCBlockUtilities freeWindowStartHour];

    NSDateComponents* comps = [cal components: (NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate: now];
    comps.hour = freeWindowStartHour;
    comps.minute = 0;
    comps.second = 0;
    NSDate* todayAtFreeWindowStart = [cal dateFromComponents: comps];

    // If the free window's start time today is still in the future, the block ends then.
    // Otherwise (we're already past it, i.e. in the free window or already back in the block
    // window), the block ends at the free window's start time tomorrow.
    if ([todayAtFreeWindowStart timeIntervalSinceNow] > 0) {
        return todayAtFreeWindowStart;
    } else {
        return [todayAtFreeWindowStart dateByAddingTimeInterval: 86400];
    }
}

@end
