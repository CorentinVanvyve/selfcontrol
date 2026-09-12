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

+ (BOOL)isInScheduledBlockWindow {
    NSCalendar* cal = [NSCalendar currentCalendar];
    NSInteger hour = [cal component: NSCalendarUnitHour fromDate: [NSDate date]];
    // Block window is 18:00 to 17:00 next day (i.e. NOT 17:00-18:00 free window)
    return hour >= 18 || hour < 17;
}

+ (NSDate*)nextScheduledBlockEndDate {
    NSCalendar* cal = [NSCalendar currentCalendar];
    NSDate* now = [NSDate date];

    NSDateComponents* comps = [cal components: (NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate: now];
    comps.hour = 17;
    comps.minute = 0;
    comps.second = 0;
    NSDate* todayAt17 = [cal dateFromComponents: comps];

    // If 17:00 today is still in the future, the block ends then.
    // Otherwise (we're past 17:00, i.e. in the 17-18 free window or just past 18:00 start), end tomorrow at 17:00.
    if ([todayAt17 timeIntervalSinceNow] > 0) {
        return todayAt17;
    } else {
        return [todayAt17 dateByAddingTimeInterval: 86400];
    }
}

@end
