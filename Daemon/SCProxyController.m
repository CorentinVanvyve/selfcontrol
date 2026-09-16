//
//  SCProxyController.m
//  org.eyebeam.selfcontrold
//

#import "SCProxyController.h"
#import "BlockManager.h"
#import <signal.h>
#import <sys/types.h>

static NSString* const kProxyWorkingDir = @"/var/root/.mitmproxy";
static NSString* const kProxyRulesJSONPath = @"/var/root/.mitmproxy/coblock_path_rules.json";
static NSString* const kProxyAddonScriptPath = @"/var/root/.mitmproxy/coblock_pathrules.py";
static NSString* const kProxyCACertPath = @"/var/root/.mitmproxy/mitmproxy-ca-cert.pem";
static NSString* const kProxyPIDPath = @"/var/root/.mitmproxy/coblock_proxy.pid";
static NSString* const kProxyPFAnchorPath = @"/etc/pf.anchors/org.eyebeam-proxy";
static NSString* const kPFConfPath = @"/etc/pf.conf";
static NSString* const kPfctlPath = @"/sbin/pfctl";
static const int kProxyListenPort = 28443;

@implementation SCProxyController

#pragma mark - mitmdump discovery

+ (nullable NSString*)mitmdumpPath {
    NSArray<NSString*>* candidates = @[
        @"/opt/homebrew/bin/mitmdump",
        @"/usr/local/bin/mitmdump",
    ];
    NSFileManager* fm = [NSFileManager defaultManager];
    for (NSString* candidate in candidates) {
        if ([fm isExecutableFileAtPath: candidate]) {
            return candidate;
        }
    }

    // fall back to searching $PATH via /usr/bin/which, in case it's somewhere non-standard
    NSTask* which = [[NSTask alloc] init];
    which.launchPath = @"/usr/bin/which";
    which.arguments = @[@"mitmdump"];
    NSPipe* pipe = [NSPipe pipe];
    which.standardOutput = pipe;
    which.standardError = [NSPipe pipe];
    @try {
        [which launch];
        NSData* data = [pipe.fileHandleForReading readDataToEndOfFile];
        [which waitUntilExit];
        if (which.terminationStatus == 0 && data.length > 0) {
            NSString* path = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
            path = [path stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (path.length > 0 && [fm isExecutableFileAtPath: path]) {
                return path;
            }
        }
    } @catch (NSException* exception) {
        NSLog(@"WARNING: Failed to search PATH for mitmdump: %@", exception);
    }

    return nil;
}

+ (BOOL)mitmdumpIsInstalled {
    return [self mitmdumpPath] != nil;
}

#pragma mark - CA setup

// mitmdump only generates its CA on a real proxy startup (not e.g. `--version`),
// so this polls briefly for the cert file to appear after we've launched it.
+ (BOOL)waitForCAFile {
    NSFileManager* fm = [NSFileManager defaultManager];
    for (int i = 0; i < 50; i++) { // up to ~5 seconds
        if ([fm fileExistsAtPath: kProxyCACertPath]) return YES;
        [NSThread sleepForTimeInterval: 0.1];
    }
    return [fm fileExistsAtPath: kProxyCACertPath];
}

+ (BOOL)trustCAIfNeeded {
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath: kProxyCACertPath]) {
        NSLog(@"ERROR: mitmdump did not generate a CA certificate at %@", kProxyCACertPath);
        return NO;
    }

    // add (or re-add - this is idempotent) our CA as a trusted root, system-wide
    NSTask* trust = [[NSTask alloc] init];
    trust.launchPath = @"/usr/bin/security";
    trust.arguments = @[@"add-trusted-cert", @"-d", @"-r", @"trustRoot", @"-k", @"/Library/Keychains/System.keychain", kProxyCACertPath];
    @try {
        [trust launch];
        [trust waitUntilExit];
    } @catch (NSException* exception) {
        NSLog(@"ERROR: Failed to trust proxy CA: %@", exception);
        return NO;
    }

    return YES;
}

+ (void)removeCATrust {
    if (![[NSFileManager defaultManager] fileExistsAtPath: kProxyCACertPath]) return;

    NSTask* untrust = [[NSTask alloc] init];
    untrust.launchPath = @"/usr/bin/security";
    untrust.arguments = @[@"remove-trusted-cert", @"-d", kProxyCACertPath];
    @try {
        [untrust launch];
        [untrust waitUntilExit];
    } @catch (NSException* exception) {
        NSLog(@"WARNING: Failed to remove proxy CA trust: %@", exception);
    }
}

#pragma mark - Addon script + rules file

+ (NSString*)addonScriptSource {
    return @"import fnmatch\n"
            "import json\n"
            "import socket\n"
            "\n"
            "from mitmproxy import ctx, http\n"
            "\n"
            "class CoblockPathRules:\n"
            "    def __init__(self):\n"
            "        self.rules = {}\n"
            "\n"
            "    def load(self, loader):\n"
            "        loader.add_option('rules_file', str, '', 'Path to the JSON path-rules file')\n"
            "\n"
            "    def configure(self, updated):\n"
            "        self._reload_rules()\n"
            "\n"
            "    def _reload_rules(self):\n"
            "        path = ctx.options.rules_file\n"
            "        if not path:\n"
            "            return\n"
            "        try:\n"
            "            with open(path) as f:\n"
            "                self.rules = json.load(f)\n"
            "        except Exception as e:\n"
            "            ctx.log.warn(f'coblock_pathrules: failed to load rules file: {e}')\n"
            "\n"
            "    def request(self, flow: http.HTTPFlow) -> None:\n"
            "        # rules can change between requests without restarting the proxy\n"
            "        self._reload_rules()\n"
            "\n"
            "        host = flow.request.pretty_host.lower()\n"
            "        patterns = self.rules.get(host)\n"
            "        if patterns is None:\n"
            "            # not one of our path-rule domains - shouldn't normally happen since\n"
            "            # only flagged domains get redirected here, but block by default just in case\n"
            "            self._block(flow, host)\n"
            "            return\n"
            "\n"
            "        target = flow.request.path or '/'\n"
            "        allowed = any(fnmatch.fnmatch(target, pattern) for pattern in patterns)\n"
            "        if not allowed:\n"
            "            self._block(flow, host)\n"
            "\n"
            "    def _block(self, flow, host):\n"
            "        flow.response = http.Response.make(\n"
            "            403,\n"
            "            f'<html><body style=\"font-family: -apple-system, sans-serif; text-align: center; margin-top: 15%;\">'\n"
            "            f'<h1>Blocked by Coblock</h1>'\n"
            "            f'<p>{host}{flow.request.path} is not on the allowed list for this block.</p>'\n"
            "            f'</body></html>',\n"
            "            {'Content-Type': 'text/html'}\n"
            "        )\n"
            "\n"
            "addons = [CoblockPathRules()]\n";
}

+ (BOOL)writeRulesFile:(NSDictionary<NSString*, NSArray<NSString*>*>*)pathRules {
    NSError* jsonErr;
    NSData* json = [NSJSONSerialization dataWithJSONObject: pathRules options: 0 error: &jsonErr];
    if (!json) {
        NSLog(@"ERROR: Failed to serialize path rules to JSON: %@", jsonErr);
        return NO;
    }
    return [json writeToFile: kProxyRulesJSONPath atomically: YES];
}

+ (BOOL)writeAddonScript {
    NSError* err;
    BOOL success = [[self addonScriptSource] writeToFile: kProxyAddonScriptPath atomically: YES encoding: NSUTF8StringEncoding error: &err];
    if (!success) {
        NSLog(@"ERROR: Failed to write proxy addon script: %@", err);
    }
    return success;
}

#pragma mark - pf redirect anchor

+ (NSArray<NSString*>*)resolveIPsForHostnames:(NSArray<NSString*>*)hostnames {
    NSMutableArray<NSString*>* ips = [NSMutableArray array];
    for (NSString* hostname in hostnames) {
        [ips addObjectsFromArray: [BlockManager ipAddressesForDomainName: hostname]];
    }
    return ips;
}

+ (void)writePFAnchorForIPs:(NSArray<NSString*>*)ips {
    NSMutableString* anchor = [NSMutableString stringWithString: @"# Coblock path-rules proxy redirect\n"];
    for (NSString* ip in ips) {
        BOOL isIPv6 = [ip containsString: @":"];
        NSString* af = isIPv6 ? @"inet6" : @"inet";
        [anchor appendFormat: @"rdr pass on lo0 %@ proto tcp from any to %@ port {80, 443} -> 127.0.0.1 port %d\n", af, ip, kProxyListenPort];
        [anchor appendFormat: @"rdr pass %@ proto tcp from any to %@ port {80, 443} -> 127.0.0.1 port %d\n", af, ip, kProxyListenPort];
    }
    [anchor writeToFile: kProxyPFAnchorPath atomically: YES encoding: NSUTF8StringEncoding error: nil];
}

+ (BOOL)pfConfContainsProxyAnchor {
    NSString* conf = [NSString stringWithContentsOfFile: kPFConfPath encoding: NSUTF8StringEncoding error: nil];
    return conf != nil && [conf rangeOfString: @"org.eyebeam-proxy"].location != NSNotFound;
}

// rdr-anchor (translation) rules must appear after normalization (scrub) rules
// but before regular anchor (filter) rules in pf.conf - pfctl enforces this
// section ordering strictly and silently refuses to (re)load an out-of-order
// file. macOS's stock pf.conf always starts with a "com.apple" scrub/nat/rdr
// block, so we insert right before the first filter-category anchor line
// (com.apple's own, or PacketFilter's appended "org.eyebeam" one) rather than
// at the very top of the file.
+ (void)ensurePFConfHasProxyAnchor {
    if ([self pfConfContainsProxyAnchor]) return;

    NSString* existing = [NSString stringWithContentsOfFile: kPFConfPath encoding: NSUTF8StringEncoding error: nil] ?: @"";
    NSString* rdrDirectives = [NSString stringWithFormat:
        @"rdr-anchor \"org.eyebeam-proxy\"\n"
        "load anchor \"org.eyebeam-proxy\" from \"%@\"\n", kProxyPFAnchorPath];

    NSArray<NSString*>* lines = [existing componentsSeparatedByString: @"\n"];
    NSUInteger insertIndex = 0;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString* trimmed = [lines[i] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix: @"anchor \""]) {
            insertIndex = i;
            break;
        }
    }

    NSMutableArray<NSString*>* newLines = [lines mutableCopy];
    [newLines insertObject: rdrDirectives atIndex: insertIndex];
    NSString* newConf = [newLines componentsJoinedByString: @"\n"];
    [newConf writeToFile: kPFConfPath atomically: YES encoding: NSUTF8StringEncoding error: nil];
}

+ (void)removePFConfProxyAnchor {
    NSString* conf = [NSString stringWithContentsOfFile: kPFConfPath encoding: NSUTF8StringEncoding error: nil];
    if (!conf) return;

    NSArray<NSString*>* lines = [conf componentsSeparatedByString: @"\n"];
    NSMutableString* newConf = [NSMutableString stringWithCapacity: conf.length];
    for (NSString* line in lines) {
        if ([line rangeOfString: @"org.eyebeam-proxy"].location == NSNotFound) {
            [newConf appendFormat: @"%@\n", line];
        }
    }
    [newConf writeToFile: kPFConfPath atomically: YES encoding: NSUTF8StringEncoding error: nil];

    [@"" writeToFile: kProxyPFAnchorPath atomically: YES encoding: NSUTF8StringEncoding error: nil];
}

+ (void)reloadPF {
    NSTask* task = [NSTask launchedTaskWithLaunchPath: kPfctlPath arguments: @[@"-f", kPFConfPath]];
    [task waitUntilExit];
}

#pragma mark - mitmdump process lifecycle

+ (nullable NSNumber*)runningPID {
    NSString* pidStr = [NSString stringWithContentsOfFile: kProxyPIDPath encoding: NSUTF8StringEncoding error: nil];
    if (!pidStr) return nil;
    pid_t pid = (pid_t)[pidStr integerValue];
    if (pid <= 0) return nil;
    // kill with signal 0 just checks whether the process exists, without actually signaling it
    if (kill(pid, 0) != 0) return nil;
    return @(pid);
}

+ (BOOL)proxyProcessIsAlive {
    return [self runningPID] != nil;
}

+ (void)stopProxyProcess {
    NSNumber* pid = [self runningPID];
    if (pid) {
        kill((pid_t)pid.intValue, SIGTERM);
    }
    [[NSFileManager defaultManager] removeItemAtPath: kProxyPIDPath error: nil];
}

+ (BOOL)startProxyProcessIfNeeded:(NSString*)mitmdumpPath {
    if ([self proxyProcessIsAlive]) return YES;

    NSTask* task = [[NSTask alloc] init];
    task.launchPath = mitmdumpPath;
    task.arguments = @[
        @"-q",
        @"--mode", @"transparent",
        @"--listen-host", @"127.0.0.1",
        @"--listen-port", [NSString stringWithFormat: @"%d", kProxyListenPort],
        @"-s", kProxyAddonScriptPath,
        @"--set", [NSString stringWithFormat: @"rules_file=%@", kProxyRulesJSONPath],
        @"--set", @"connection_strategy=lazy",
    ];
    task.environment = @{@"HOME": @"/var/root"};

    @try {
        [task launch];
    } @catch (NSException* exception) {
        NSLog(@"ERROR: Failed to launch mitmdump: %@", exception);
        return NO;
    }

    NSString* pidStr = [NSString stringWithFormat: @"%d", task.processIdentifier];
    [pidStr writeToFile: kProxyPIDPath atomically: YES encoding: NSUTF8StringEncoding error: nil];
    return YES;
}

#pragma mark - Public API

+ (BOOL)startOrUpdateWithPathRules:(NSDictionary<NSString*, NSArray<NSString*>*>*)pathRules {
    if (pathRules.count == 0) {
        [self stop];
        return YES;
    }

    NSString* mitmdumpPath = [self mitmdumpPath];
    if (!mitmdumpPath) {
        NSLog(@"WARNING: Path rules are configured but mitmdump isn't installed (brew install mitmproxy). Those domains will be fully inaccessible until it is.");
        return NO;
    }

    [[NSFileManager defaultManager] createDirectoryAtPath: kProxyWorkingDir withIntermediateDirectories: YES attributes: @{NSFilePosixPermissions: @0700} error: nil];
    [self writeAddonScript];
    [self writeRulesFile: pathRules];

    BOOL wasAlreadyRunning = [self proxyProcessIsAlive];
    if (![self startProxyProcessIfNeeded: mitmdumpPath]) {
        return NO;
    }

    // first run: mitmdump only generates its CA once it actually starts up as a
    // proxy, so give it a moment and then trust it before routing traffic to it
    if (!wasAlreadyRunning) {
        [self waitForCAFile];
    }
    if (![self trustCAIfNeeded]) {
        return NO;
    }

    NSArray<NSString*>* ips = [self resolveIPsForHostnames: pathRules.allKeys];
    [self writePFAnchorForIPs: ips];
    [self ensurePFConfHasProxyAnchor];
    [self reloadPF];

    return YES;
}

+ (void)stop {
    [self stopProxyProcess];
    [self removePFConfProxyAnchor];
    [self reloadPF];
    [self removeCATrust];
}

+ (BOOL)isMissingOrDeadForPathRules:(NSDictionary<NSString*, NSArray<NSString*>*>*)pathRules {
    if (pathRules.count == 0) return NO;
    return ![self proxyProcessIsAlive];
}

@end
