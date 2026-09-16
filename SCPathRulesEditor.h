//
//  SCPathRulesEditor.h
//  Coblock
//
//  A small, user-friendly editor for per-domain "path rules": lets a blocked
//  domain (e.g. youtube.com) still allow specific URL paths (e.g. /watch*).
//  Presented as a sheet on top of the domain list window.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCPathRulesEditor : NSObject

// Shows a sheet (on parentWindow) for editing the allowed path patterns for
// hostname. Patterns are stored in NSUserDefaults under "PathRules", keyed by
// lowercased hostname, and this reads/writes that key directly.
+ (void)editPathRulesForHostname:(NSString*)hostname inWindow:(nullable NSWindow*)parentWindow;

@end

NS_ASSUME_NONNULL_END
