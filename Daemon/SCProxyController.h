//
//  SCProxyController.h
//  org.eyebeam.selfcontrold
//
//  Manages the local path-rules proxy: a transparent HTTPS-intercepting
//  mitmdump process (external dependency, `brew install mitmproxy`) that lets
//  specific URL paths through on an otherwise-blocked domain (e.g. block
//  youtube.com but allow /watch*). Traffic for path-rule domains is redirected
//  to the proxy via a dedicated pf rdr anchor, kept separate from the normal
//  org.eyebeam block/allow anchor managed by PacketFilter.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCProxyController : NSObject

// (Re)starts the path-rules proxy and pf redirect rules for the given rules,
// or updates the rules file in place if already running. pathRules maps
// lowercase hostname -> array of allowed path+query glob patterns (e.g. "/watch*").
// Safe to call with an empty/nil dictionary, which just stops everything.
// Returns NO if mitmdump isn't installed - the caller should surface this to
// the user, but it's non-fatal to the rest of the block.
+ (BOOL)startOrUpdateWithPathRules:(nullable NSDictionary<NSString*, NSArray<NSString*>*>*)pathRules;

// Stops the mitmdump process, removes the pf redirect anchor, and removes the
// proxy's CA from the System keychain's trusted roots.
+ (void)stop;

// YES if pathRules is non-empty but the mitmdump process isn't actually running
// (e.g. it crashed) - used by the daemon's periodic integrity checkup.
+ (BOOL)isMissingOrDeadForPathRules:(nullable NSDictionary<NSString*, NSArray<NSString*>*>*)pathRules;

// YES if the `mitmdump` binary can be found (Homebrew's usual install paths, or $PATH).
+ (BOOL)mitmdumpIsInstalled;

@end

NS_ASSUME_NONNULL_END
