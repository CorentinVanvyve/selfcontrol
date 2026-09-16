//
//  SCPathRulesEditor.m
//  Coblock
//

#import "SCPathRulesEditor.h"

@implementation SCPathRulesEditor

+ (BOOL)mitmdumpIsInstalled {
    NSFileManager* fm = [NSFileManager defaultManager];
    for (NSString* candidate in @[@"/opt/homebrew/bin/mitmdump", @"/usr/local/bin/mitmdump"]) {
        if ([fm isExecutableFileAtPath: candidate]) return YES;
    }
    return NO;
}

+ (void)editPathRulesForHostname:(NSString*)hostname inWindow:(nullable NSWindow*)parentWindow {
    NSString* key = hostname.lowercaseString;
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary<NSString*, NSArray<NSString*>*>* allPathRules = [defaults dictionaryForKey: @"PathRules"] ?: @{};
    NSArray<NSString*>* existingPatterns = allPathRules[key] ?: @[];

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat: NSLocalizedString(@"Path Rules for %@", @"Path rules editor title"), hostname];
    alert.informativeText = NSLocalizedString(@"This domain will still be blocked, except for pages whose URL matches one of these patterns (one per line). Use * as a wildcard - for example, /watch* allows any YouTube video page.", @"Path rules editor explanation");
    [alert addButtonWithTitle: NSLocalizedString(@"Save", @"Save button")];
    [alert addButtonWithTitle: NSLocalizedString(@"Cancel", @"Cancel button")];

    NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 360, 100)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    NSTextView* textView = [[NSTextView alloc] initWithFrame: scrollView.bounds];
    textView.string = [existingPatterns componentsJoinedByString: @"\n"];
    textView.font = [NSFont userFixedPitchFontOfSize: 12];
    textView.minSize = NSMakeSize(0, 100);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.widthTracksTextView = YES;

    scrollView.documentView = textView;
    alert.accessoryView = scrollView;

    if (![self mitmdumpIsInstalled]) {
        alert.informativeText = [alert.informativeText stringByAppendingString:
            NSLocalizedString(@"\n\nNote: this feature requires mitmproxy, which isn't installed yet. Install it with: brew install mitmproxy. You can still save this rule now - it'll take effect once mitmproxy is installed and a block is (re)started.", @"mitmproxy missing warning")];
    }

    void (^handleResponse)(NSModalResponse) = ^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return; // Cancel

        NSArray<NSString*>* patterns = [textView.string componentsSeparatedByString: @"\n"];
        NSMutableArray<NSString*>* cleanedPatterns = [NSMutableArray arrayWithCapacity: patterns.count];
        for (NSString* pattern in patterns) {
            NSString* trimmed = [pattern stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [cleanedPatterns addObject: trimmed];
            }
        }

        NSMutableDictionary<NSString*, NSArray<NSString*>*>* newAllPathRules = [allPathRules mutableCopy];
        if (cleanedPatterns.count > 0) {
            newAllPathRules[key] = cleanedPatterns;
        } else {
            [newAllPathRules removeObjectForKey: key];
        }

        [defaults setObject: newAllPathRules forKey: @"PathRules"];
        [[NSNotificationCenter defaultCenter] postNotificationName: @"SCConfigurationChangedNotification" object: self];
    };

    if (parentWindow != nil) {
        [alert beginSheetModalForWindow: parentWindow completionHandler: handleResponse];
    } else {
        handleResponse([alert runModal]);
    }
}

@end
