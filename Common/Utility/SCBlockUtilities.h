//
//  SCBlockUtilities.h
//  SelfControl
//
//  Created by Charlie Stigler on 1/19/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCBlockUtilities : NSObject

// uses the below methods as well as filesystem checks to see if the block is REALLY running or not
+ (BOOL)anyBlockIsRunning;
+ (BOOL)modernBlockIsRunning;
+ (BOOL)legacyBlockIsRunning;

+ (BOOL)currentBlockIsExpired;

+ (BOOL)blockRulesFoundOnSystem;

+ (void)removeBlockFromSettings;

// Returns YES if we're currently in the free/edit window (i.e. NOT the scheduled block window).
// The free window is configured via FreeWindowStartHour/FreeWindowEndHour in SCSettings
// (defaults 17/18, matching the original hardcoded 17:00-18:00 free window).
+ (BOOL)isInScheduledBlockWindow;

// Returns the next free-window start time (today if it hasn't happened yet, tomorrow otherwise) -
// this is when a scheduled block should end.
+ (NSDate*)nextScheduledBlockEndDate;

// The currently configured free-window bounds (reads SCSettings, falls back to 17/18).
+ (NSInteger)freeWindowStartHour;
+ (NSInteger)freeWindowEndHour;

// Pure, wrap-aware helpers shared by validation (app + daemon) and the window check above.
// Duration treats start==end as 0 hours (i.e. invalid/degenerate), not 24.
+ (NSInteger)freeWindowDurationHoursFromStart:(NSInteger)startHour end:(NSInteger)endHour;
+ (BOOL)isHour:(NSInteger)hour inWindowFromStart:(NSInteger)startHour end:(NSInteger)endHour;

@end

NS_ASSUME_NONNULL_END
