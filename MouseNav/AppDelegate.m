//
//  AppDelegate.m
//  MouseNav
//
//  Created by George MacKerron on 17/03/2021.
//

#import "AppDelegate.h"
#define MaxEvents 1024
#define MinGesturePixels 48
#define MaxWobblePixels 2

#ifdef DEBUG
#define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define DLog(...)
#endif

typedef NS_ENUM(NSInteger, GestureState) {
  GestureStateAwaiting,
  GestureStateMovingLeft,
  GestureStateMovingRight,
  GestureStateAborted,  // so we pass events through until and including mouse up
  GestureStateCompleted // so we swallow events until and including mouse up
};

typedef NS_ENUM(NSInteger, AppPref) {
  AppPrefCmdBrackets = 0,
  AppPrefDisabled = 1,
  AppPrefCmdCtrlArrows = 2,
  AppPrefCtrlShiftDash = 3
};

@interface AppDelegate ()

@property (strong) NSStatusItem *statusItem;

@end

@implementation AppDelegate

static CFMachPortRef mouseEventTap = NULL;
static CFRunLoopSourceRef runLoopSource = NULL;

static GestureState gestureState = GestureStateAwaiting;
static CGEventRef events[MaxEvents];
static size_t nextEventsIndex = 0;

- (void)quit {
  [NSApplication.sharedApplication terminate:self];
}

- (void)setAppPref:(AppPref)appPref {
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  NSString *frontBundleId = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
  if (appPref == 0) [defs removeObjectForKey:frontBundleId];
  else [defs setInteger:appPref forKey:frontBundleId];
  [defs synchronize];
}

- (void)brackets {
  [self setAppPref:AppPrefCmdBrackets];
}

- (void)arrows {
  [self setAppPref:AppPrefCmdCtrlArrows];
}

- (void)dash {
  [self setAppPref:AppPrefCtrlShiftDash];
}

- (void)none {
  [self setAppPref:AppPrefDisabled];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
  NSRunningApplication *frontApp = NSWorkspace.sharedWorkspace.frontmostApplication;
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  AppPref appPref = [defs integerForKey:frontApp.bundleIdentifier];
  
  NSMenuItem *item = menu.itemArray.firstObject;
  item.title = frontApp.localizedName;
  item.submenu = [NSMenu.alloc initWithTitle:@"Current app"];
  
  NSMenuItem *subItem;
  subItem = [item.submenu addItemWithTitle:@"Send ⌘[ and ⌘]" action:@selector(brackets) keyEquivalent:@""];
  subItem.state = appPref == 0 ? NSOnState : NSOffState;
  
  subItem = [item.submenu addItemWithTitle:@"Send ⌃⌘← and ⌃⌘→" action:@selector(arrows) keyEquivalent:@""];
  subItem.state = appPref == 2 ? NSOnState : NSOffState;
  
  subItem = [item.submenu addItemWithTitle:@"Send ⌃- and ⌃⇧-" action:@selector(dash) keyEquivalent:@""];
  subItem.state = appPref == 3 ? NSOnState : NSOffState;
  
  subItem = [item.submenu addItemWithTitle:@"Disable gestures" action:@selector(none) keyEquivalent:@""];
  subItem.state = appPref == 1 ? NSOnState : NSOffState;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  [NSUserDefaults.standardUserDefaults registerDefaults:@{
    @"com.apple.dt.Xcode": @(AppPrefCmdCtrlArrows),
    @"com.microsoft.VSCode": @(AppPrefCtrlShiftDash),
    @"com.sublimetext.3": @(AppPrefCtrlShiftDash),
    @"nl.ultimaker.cura": @(AppPrefDisabled),
  }];
  
  NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
  NSStatusItem *item = [statusBar statusItemWithLength:NSVariableStatusItemLength];
  item.button.title = @"⟺";
  item.menu = [NSMenu.alloc initWithTitle:@"MouseNav"];
  [item.menu addItemWithTitle:@"Current app" action:NULL keyEquivalent:@""];
  [item.menu addItemWithTitle:@"Quit MouseNav" action:@selector(quit) keyEquivalent:@""];
  item.menu.delegate = self;
  self.statusItem = item;
  
  CGEventMask eventMask = (CGEventMaskBit(kCGEventRightMouseDown) |
                           CGEventMaskBit(kCGEventRightMouseDragged) |
                           CGEventMaskBit(kCGEventRightMouseUp));
  
  mouseEventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, eventMask, mouseEventCallback, NULL);
  
  const void *keys[] = { kAXTrustedCheckOptionPrompt };
  const void *values[] = { kCFBooleanTrue };
  CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, keys, values, sizeof(keys) / sizeof(*keys),
                                               &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions(options);
  
  if (accessibilityEnabled) {
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseEventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
  } else {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"GestureNav processes mouse events, and requires Accessibility permissions to work";
    alert.informativeText = @"Please go to System Preferences → Security & Privacy → Privacy → Accessibility and enable for GestureNav.";
    __unused NSModalResponse response = [alert runModal];
    [NSApplication.sharedApplication terminate:self];
  }
}

static CGEventRef mouseEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
  NSRunningApplication *frontApp = NSWorkspace.sharedWorkspace.frontmostApplication;
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  NSInteger appPref = [defs integerForKey:frontApp.bundleIdentifier];
  
  NSPoint location = CGEventGetLocation(event);
  DLog(@"%u %f %f", type, location.x, location.y);
  
  if (type == kCGEventTapDisabledByUserInput || type == kCGEventTapDisabledByTimeout) {
    DLog(@"Re-enabling");
    CGEventTapEnable(mouseEventTap, true);  // re-enable
  }
  
  if (appPref == AppPrefDisabled) return event;
  
  switch (gestureState) {
    case GestureStateAborted:
      if (type == kCGEventRightMouseUp) gestureState = GestureStateAwaiting;
      return event;  // pass on all events if aborted
      
    case GestureStateCompleted:
      if (type == kCGEventRightMouseUp) gestureState = GestureStateAwaiting;
      return NULL;  // swallow all events if completed
      
    case GestureStateAwaiting:
    case GestureStateMovingLeft:
    case GestureStateMovingRight:
      
      switch (type) {
        case kCGEventRightMouseUp:
          clearEvents(proxy);
          gestureState = GestureStateAwaiting;
          return event;
          
        case kCGEventRightMouseDown:
          DLog(@"--- (%lu)", nextEventsIndex);
          clearEvents(NULL);  // make sure everything's reset
          // do not 'break;' here
          
        case kCGEventRightMouseDragged:
          if (nextEventsIndex > 0) {
            CGEventRef prevEvent = events[nextEventsIndex - 1];
            CGPoint prevLocation = CGEventGetLocation(prevEvent);
            CGFloat xPrevDelta = location.x - prevLocation.x;
            CGFloat yPrevDeltaAbs = fabs(location.y - prevLocation.y);
            
            CGEventRef firstEvent = events[0];
            CGPoint firstLocation = CGEventGetLocation(firstEvent);
            CGFloat xFirstDelta = location.x - firstLocation.x;
            CGFloat yFirstDeltaAbs = fabs(location.y - firstLocation.y);
            
            BOOL movingLeft = xPrevDelta < -MaxWobblePixels && yPrevDeltaAbs < -xPrevDelta;
            BOOL movingRight = xPrevDelta > MaxWobblePixels && yPrevDeltaAbs < xPrevDelta;
            
            if ((gestureState == GestureStateMovingLeft && movingRight) ||
                (gestureState == GestureStateMovingRight && movingLeft) ||
                (yPrevDeltaAbs > fabs(xPrevDelta) && yPrevDeltaAbs > MaxWobblePixels) ||
                yFirstDeltaAbs > MinGesturePixels ||
                nextEventsIndex >= MaxEvents) {
              
              clearEvents(proxy);
              gestureState = GestureStateAborted;
              return event;
            }
            
            if (movingLeft) gestureState = GestureStateMovingLeft;
            if (movingRight) gestureState = GestureStateMovingRight;
            
            if (xFirstDelta <= -MinGesturePixels) {
              DLog(@"Back");
              sendNavCmd(appPref, NO);
              clearEvents(NULL);
              gestureState = GestureStateCompleted;
              return NULL;
            }
            
            if (xFirstDelta >= MinGesturePixels) {
              DLog(@"Forward");
              sendNavCmd(appPref, YES);
              clearEvents(NULL);
              gestureState = GestureStateCompleted;
              return NULL;
            }
          }
          
          CFRetain(event);
          events[nextEventsIndex++] = event;
          return NULL;
          
        default:
          DLog(@"Surprise event");
          return event;
      }
  }
}

static void clearEvents(CGEventTapProxy sendProxy) {
  for (NSUInteger i = 0; i < nextEventsIndex; i ++) {
    CGEventRef event = events[i];
    if (sendProxy) CGEventTapPostEvent(sendProxy, event);  // should be released by system
    CFRelease(event);
  }
  nextEventsIndex = 0;
}

static void sendNavCmd(AppPref appPref, BOOL forward) {
  CGKeyCode virtualKey = 0x0;
  CGEventFlags flags = 0;
  
  switch(appPref) {
    case AppPrefCmdBrackets:
      virtualKey = forward ? 0x1E : 0x21;
      flags = kCGEventFlagMaskCommand;
      break;
      
    case AppPrefCmdCtrlArrows:
      virtualKey = forward ? 0x7C : 0x7B;
      flags = kCGEventFlagMaskCommand | kCGEventFlagMaskControl;
      break;
    
    case AppPrefCtrlShiftDash:
      virtualKey = 0x1B;
      flags = forward ? kCGEventFlagMaskControl | kCGEventFlagMaskShift : kCGEventFlagMaskControl;
      break;
  }

  CGEventRef keydown = CGEventCreateKeyboardEvent(NULL, virtualKey, true);
  CGEventSetFlags(keydown, flags);
  CGEventPost(kCGSessionEventTap, keydown);
  CFRelease(keydown);
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
  if (runLoopSource) {
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CFRelease(runLoopSource);
  }
  CFRelease(mouseEventTap);
}

@end
