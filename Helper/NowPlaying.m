// Musicfy's window into the system's Now Playing (MediaRemote), for apps with no
// AppleScript, such as Podcasts.
//
// Since macOS 15.4 MediaRemote only answers Apple's own processes, so this library is
// loaded by /usr/bin/perl (an Apple binary) through Resources/now-playing.pl. It runs
// until stdin closes, which happens when Musicfy quits.
//
// Out (stdout), one JSON object per line, whenever something changes:
//   {"bundle", "parent", "playing", "title", "artist", "album", "duration",
//    "position", "id", "artworkTag", "artwork" (base64, only when it changed)}
//   {"bundle": ""} when nothing is loaded.
// In (stdin), one command per line: play, pause, toggle, next, previous, seek <seconds>.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientString)(id);
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(int, CFDictionaryRef);
typedef void (*MRSetElapsed)(double);

static MRGetInfo getInfo;
static MRGetIsPlaying getIsPlaying;
static MRGetClient getClient;
static MRClientString clientBundle;
static MRClientString clientParent;
static MRRegister registerNotifications;
static MRSendCommand sendCommand;
static MRSetElapsed setElapsed;

static dispatch_queue_t queue;
static NSUInteger lastArtworkHash;
static BOOL emitScheduled;

static void writeLine(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *string(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static double number(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0;
}

static void emit(void) {
    getClient(queue, ^(id client) {
        NSString *bundle = client && clientBundle ? (__bridge NSString *)clientBundle(client) : nil;
        NSString *parent = client && clientParent ? (__bridge NSString *)clientParent(client) : nil;
        getInfo(queue, ^(CFDictionaryRef raw) {
            NSDictionary *info = (__bridge NSDictionary *)raw;
            void (^finish)(BOOL) = ^(BOOL playing) {
                if (!info || info.count == 0) {
                    lastArtworkHash = 0;
                    writeLine(@{@"bundle": @""});
                    return;
                }
                // The elapsed time is as of `Timestamp`; bring it to now.
                double elapsed = number(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
                double rate = number(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
                id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if (playing && rate > 0 && [stamp isKindOfClass:[NSDate class]]) {
                    elapsed += -[(NSDate *)stamp timeIntervalSinceNow] * rate;
                }
                NSString *identifier = string(info, @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier");
                if (identifier.length == 0) {
                    id unique = info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"];
                    if (unique) identifier = [unique description];
                }
                NSMutableDictionary *out = [@{
                    @"bundle": bundle ?: @"",
                    @"parent": parent ?: @"",
                    @"playing": @(playing),
                    @"title": string(info, @"kMRMediaRemoteNowPlayingInfoTitle"),
                    @"artist": string(info, @"kMRMediaRemoteNowPlayingInfoArtist"),
                    @"album": string(info, @"kMRMediaRemoteNowPlayingInfoAlbum"),
                    @"duration": @(number(info, @"kMRMediaRemoteNowPlayingInfoDuration")),
                    @"position": @(MAX(0, elapsed)),
                    @"id": identifier ?: @"",
                } mutableCopy];
                id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([artwork isKindOfClass:[NSData class]] && [artwork length] > 0) {
                    NSData *data = artwork;
                    NSUInteger hash = data.length ^ (data.hash << 1);
                    out[@"artworkTag"] = [NSString stringWithFormat:@"%lx", (unsigned long)hash];
                    if (hash != lastArtworkHash) {
                        out[@"artwork"] = [data base64EncodedStringWithOptions:0];
                        lastArtworkHash = hash;
                    }
                } else {
                    out[@"artworkTag"] = @"";
                    lastArtworkHash = 0;
                }
                writeLine(out);
            };
            if (getIsPlaying) {
                getIsPlaying(queue, ^(Boolean playing) { finish(playing); });
            } else {
                finish(number(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate") > 0);
            }
        });
    });
}

/// Changes come in bursts (info, then artwork, then the playing flag): one line for all.
static void scheduleEmit(void) {
    dispatch_async(queue, ^{
        if (emitScheduled) return;
        emitScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), queue, ^{
            emitScheduled = NO;
            emit();
        });
    });
}

static void handle(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *verb = parts.firstObject;
    // MRMediaRemoteCommand: 0 play, 1 pause, 2 toggle, 4 next track, 5 previous track.
    if ([verb isEqualToString:@"play"]) sendCommand(0, NULL);
    else if ([verb isEqualToString:@"pause"]) sendCommand(1, NULL);
    else if ([verb isEqualToString:@"toggle"]) sendCommand(2, NULL);
    else if ([verb isEqualToString:@"next"]) sendCommand(4, NULL);
    else if ([verb isEqualToString:@"previous"]) sendCommand(5, NULL);
    else if ([verb isEqualToString:@"seek"] && parts.count > 1 && setElapsed) setElapsed(MAX(0, parts[1].doubleValue));
    else if ([verb isEqualToString:@"refresh"]) {}
    else return;
    scheduleEmit();
}

static void readCommands(void) {
    [NSThread detachNewThreadWithBlock:^{
        char *buffer = NULL;
        size_t capacity = 0;
        ssize_t length;
        while ((length = getline(&buffer, &capacity, stdin)) > 0) {
            NSString *line = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length) dispatch_async(queue, ^{ handle(line); });
        }
        exit(0); // Musicfy is gone.
    }];
}

/// Called by perl as an XSUB; its arguments are ignored. Never returns.
void musicfy_now_playing_run(void *perl, void *cv) {
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!mr) {
            writeLine(@{@"error": @"MediaRemote not found"});
            exit(1);
        }
        getInfo = (MRGetInfo)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        getIsPlaying = (MRGetIsPlaying)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        getClient = (MRGetClient)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        clientBundle = (MRClientString)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        clientParent = (MRClientString)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        registerNotifications = (MRRegister)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        sendCommand = (MRSendCommand)dlsym(mr, "MRMediaRemoteSendCommand");
        setElapsed = (MRSetElapsed)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        if (!getInfo || !getClient || !registerNotifications || !sendCommand) {
            writeLine(@{@"error": @"MediaRemote functions missing"});
            exit(1);
        }
        queue = dispatch_queue_create("musicfy.nowplaying", DISPATCH_QUEUE_SERIAL);

        registerNotifications(queue);
        NSArray *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        ];
        for (NSString *name in names) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                scheduleEmit();
            }];
        }
        if (getenv("MUSICFY_NP_ONCE")) {
            // Diagnostics: print what's playing and quit (the artwork may follow in a second line).
            emit();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), queue, ^{ exit(0); });
        } else {
            readCommands();
            scheduleEmit();
        }
    }
    CFRunLoopRun();
    exit(0);
}
