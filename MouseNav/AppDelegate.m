//
//  AppDelegate.m
//  MouseNav
//
//  Created by George MacKerron on 17/03/2021.
//

#import "AppDelegate.h"
#import "NSLabel.h"

#include <Carbon/Carbon.h>

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

// defaults = British/US values
static CGKeyCode openBracketKeycode = 0x21;
static CGEventFlags openBracketFlags = 0;

static CGKeyCode closeBracketKeycode = 0x1E;
static CGEventFlags closeBracketFlags = 0;

static CGKeyCode dashKeycode = 0x1B;
static CGEventFlags dashFlags = 0;

// these ones don't change
static CGKeyCode leftArrowKeycode = 0x7B;
static CGKeyCode rightArrowKeycode = 0x7C;

- (void)quit {
  [NSApplication.sharedApplication terminate:self];
}

- (void)setAppPref:(AppPref)appPref {
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  NSString *frontBundleId = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
  [defs setInteger:appPref forKey:frontBundleId];
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

- (void)setBackShortcut {
  DLog(@"tap");
  CGEventMask eventMask = (CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp));
  CFMachPortRef keyEventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, eventMask, keyEventCallback, NULL);
  CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyEventTap, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
}

static CGEventRef keyEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
  DLog(@"key");
  UniChar chars[12];
  UniCharCount charCount;
  CGEventKeyboardGetUnicodeString(event, 12, &charCount, chars);
  NSInteger keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
  
  NSString *str = [NSString stringWithCharacters:chars length:charCount];
  DLog(@"%u str: %@ charcount: %lu charcode: %u keycode: %lu", CGEventGetType(event), str, charCount, chars[0], keycode);
  return NULL;
}

- (void)setForwardShortcut {
  
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
  NSRunningApplication *frontApp = NSWorkspace.sharedWorkspace.frontmostApplication;
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  AppPref appPref = [defs integerForKey:frontApp.bundleIdentifier];
  
  [menu removeAllItems];
  
  NSMenuItem *item;
  NSString *title = frontApp.localizedName;
  NSFont *titleFont = [NSFontManager.sharedFontManager convertFont:[NSFont menuFontOfSize:0.0]
                                                       toHaveTrait:NSBoldFontMask];
  
  item = [menu addItemWithTitle:title action:NULL keyEquivalent:@""];
  item.attributedTitle = [NSAttributedString.alloc initWithString:title
                                                       attributes:@{NSFontAttributeName: titleFont}];
  
  item = [menu addItemWithTitle:@"For back and forward ..." action:NULL keyEquivalent:@""];
  
  NSMutableParagraphStyle *p = NSMutableParagraphStyle.new;
  p.lineHeightMultiple = 2.0;
  
  item = [menu addItemWithTitle:@"Send ⌘[ and ⌘]" action:@selector(brackets) keyEquivalent:@""];
  item.state = appPref == 0 ? NSOnState : NSOffState;
  
  item = [menu addItemWithTitle:@"Send ⌃⌘← and ⌃⌘→" action:@selector(arrows) keyEquivalent:@""];
  item.state = appPref == 2 ? NSOnState : NSOffState;
  
  item = [menu addItemWithTitle:@"Send ⌃- and ⌃⇧-" action:@selector(dash) keyEquivalent:@""];
  item.state = appPref == 3 ? NSOnState : NSOffState;
  
  
  item = [NSMenuItem.alloc initWithTitle:@"X" action:nil keyEquivalent:@""];
  NSView *view = [NSView.alloc initWithFrame:CGRectZero];
  
  NSLabel *sendLabel = NSLabel.new;
  sendLabel.stringValue = @"Send";
  sendLabel.font = [NSFont menuFontOfSize:0.0];
  
  NSLabel *andLabel = NSLabel.new;
  andLabel.stringValue = @"and";
  andLabel.font = [NSFont menuFontOfSize:0.0];
  
  NSButton *backBtn = [NSButton buttonWithTitle:@"⌘[" target:self action:@selector(setBackShortcut)];
  NSButton *fwdBtn = [NSButton buttonWithTitle:@"⌘]" target:self action:@selector(setForwardShortcut)];
  
  [view addSubview:sendLabel];
  [view addSubview:backBtn];
  [view addSubview:andLabel];
  [view addSubview:fwdBtn];
  
  view.translatesAutoresizingMaskIntoConstraints =
  sendLabel.translatesAutoresizingMaskIntoConstraints =
  andLabel.translatesAutoresizingMaskIntoConstraints = backBtn.translatesAutoresizingMaskIntoConstraints = fwdBtn.translatesAutoresizingMaskIntoConstraints = NO;
  
  [NSLayoutConstraint activateConstraints:@[
    [sendLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24.0],
    [backBtn.leadingAnchor constraintEqualToAnchor:sendLabel.trailingAnchor constant:6.0],
    [andLabel.leadingAnchor constraintEqualToAnchor:backBtn.trailingAnchor constant:6.0],
    [fwdBtn.leadingAnchor constraintEqualToAnchor:andLabel.trailingAnchor constant:6.0],
    [view.trailingAnchor constraintGreaterThanOrEqualToAnchor:fwdBtn.trailingAnchor constant:20.0],
    
    [backBtn.topAnchor constraintEqualToAnchor:view.topAnchor constant: 2.0],
    [sendLabel.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
    [view.bottomAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant: 2.0],
    [andLabel.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
    [view.bottomAnchor constraintEqualToAnchor:fwdBtn.bottomAnchor constant: 2.0],
  ]];
  
  item.view = view;
  [menu addItem:item];
  
  item = [menu addItemWithTitle:@"Do nothing" action:@selector(none) keyEquivalent:@""];
  item.state = appPref == 1 ? NSOnState : NSOffState;
  
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItemWithTitle:@"Start at login" action:@selector(quit) keyEquivalent:@""];
  [menu addItemWithTitle:@"About MouseNav (1.0)" action:@selector(quit) keyEquivalent:@""];
  [menu addItemWithTitle:@"Quit MouseNav" action:@selector(quit) keyEquivalent:@""];
}

CGEventFlags eventFlagsFromModifiers(UInt32 modifiers) {
  CGEventFlags result = 0;
  if (modifiers & shiftKey) {
    result |= kCGEventFlagMaskShift;
    DLog(@"Shift");
  }
  if (modifiers & optionKey) {
    result |= kCGEventFlagMaskAlternate;
    DLog(@"Option");
  }
  if (modifiers & controlKey) {
    result |= kCGEventFlagMaskControl;
    DLog(@"Control");
  }
  if (modifiers & cmdKey) {
    result |= kCGEventFlagMaskCommand;
    DLog(@"Command");
  }
  return result;
}

- (void)keyboardChanged {
  static UInt32 modifierKeyStates[] = {
    0,
    shiftKey,  // good bet for [ and ] (Spanish)
    optionKey,  // good bet for [ and ] (German and Azeri)
    optionKey | shiftKey,  // good bet for [ and ] (French)
    controlKey,
    optionKey | controlKey,
    controlKey | shiftKey,
    optionKey | shiftKey | controlKey
  };
  size_t modifiersLength = sizeof(modifierKeyStates) / sizeof(UInt32);
  
  TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
  CFStringRef keyboardName = (CFStringRef)TISGetInputSourceProperty(source, kTISPropertyLocalizedName);
  CFStringRef keyboardID = (CFStringRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
  DLog(@"Keyboard: %@ (%@)", keyboardName, keyboardID);
  
  CFDataRef layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
  const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
  
  UInt32 keyboardType = LMGetKbdType();
  UInt32 deadKeyState = 0;
  UniCharCount actualStringLength;
  UniChar unicodeChar[255] = {0};
  
  BOOL foundOpenBracket = NO;
  BOOL foundCloseBracket = NO;
  BOOL foundDash = NO;
  
  for (size_t i = 0; i < modifiersLength; i++) {
    UInt32 modifiers = modifierKeyStates[i];
    UInt32 modifierKeyState = (modifiers >> 8) & 0xFF;
    for (UInt16 keycode = 0; keycode < 128; keycode++) {
      OSStatus resultCode = UCKeyTranslate(keyboardLayout,
                                           keycode,
                                           kUCKeyActionUp, // kUCKeyActionDown fails for Azeri (Azerbaijani) -- why??
                                           modifierKeyState,
                                           keyboardType,
                                           kUCKeyTranslateNoDeadKeysBit,
                                           &deadKeyState,
                                           255,
                                           &actualStringLength,
                                           unicodeChar);
      
      if (resultCode == noErr) {
        if (actualStringLength == 1) {
          UniChar c = unicodeChar[0];
          if (!foundOpenBracket && c == '[') {
            openBracketKeycode = keycode;
            openBracketFlags = eventFlagsFromModifiers(modifiers);
            foundOpenBracket = YES;
            DLog(@"char: %c keycode: %d modifiers: %#04x", (char)unicodeChar[0], keycode, modifierKeyState);
            
          } else if (!foundCloseBracket && c == ']') {
            closeBracketKeycode = keycode;
            closeBracketFlags = eventFlagsFromModifiers(modifiers);
            foundCloseBracket = YES;
            DLog(@"char: %c keycode: %d modifiers: %#04x", (char)unicodeChar[0], keycode, modifierKeyState);
            
          } else if (!foundDash && c == '-') {
            dashKeycode = keycode;
            dashFlags = eventFlagsFromModifiers(modifiers);
            foundDash = YES;
            DLog(@"char: %c keycode: %d modifiers: %#04x", (char)unicodeChar[0], keycode, modifierKeyState);
          }
        }
      } else {
        DLog(@"Error translating %d (%#04x): %d",  keycode, modifierKeyState, resultCode);
      }
      
      if (foundOpenBracket && foundCloseBracket && foundDash) return;
    }
  }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  [self keyboardChanged];
  [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                    selector:@selector(keyboardChanged)
                                                        name:(__bridge NSString*)kTISNotifySelectedKeyboardInputSourceChanged
                                                      object:nil
                                          suspensionBehavior:NSNotificationSuspensionBehaviorCoalesce];
  
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
  item.menu.delegate = self;
  self.statusItem = item;  // not retained if we omit this
  
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
    alert.messageText = @"MouseNav requires Accessibility permissions";
    alert.informativeText = @"Go to System Preferences → Security & Privacy → Privacy → Accessibility, and enable MouseNav. Then re-open the app.";
    [alert runModal];
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
    if (sendProxy) CGEventTapPostEvent(sendProxy, event);
    CFRelease(event);  // balancing the manual CFRetain above
  }
  nextEventsIndex = 0;
}

static void sendNavCmd(AppPref appPref, BOOL forward) {
  CGKeyCode virtualKey = 0x0;
  CGEventFlags flags = 0;
  
  switch(appPref) {
    case AppPrefCmdBrackets:
      virtualKey = forward ? closeBracketKeycode : openBracketKeycode;
      flags = kCGEventFlagMaskCommand | (forward ? closeBracketFlags : openBracketFlags);
      break;
      
    case AppPrefCmdCtrlArrows:
      virtualKey = forward ? rightArrowKeycode : leftArrowKeycode;
      flags = kCGEventFlagMaskCommand | kCGEventFlagMaskControl;
      break;
      
    case AppPrefCtrlShiftDash:
      virtualKey = dashKeycode;
      flags = (forward ? kCGEventFlagMaskControl | kCGEventFlagMaskShift : kCGEventFlagMaskControl) | dashFlags;
      break;
  }
  
  CGEventRef keydown = CGEventCreateKeyboardEvent(NULL, virtualKey, true);
  CGEventSetFlags(keydown, flags);
  
  //  UniChar character[1];
  //  [@"[" getCharacters:character range:NSMakeRange(0, 1)];
  //  CGEventKeyboardSetUnicodeString(keydown, 1, character);
  
  CGEventPost(kCGSessionEventTap, keydown);
  CFRelease(keydown);
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
  if (runLoopSource) {
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CFRelease(runLoopSource);
  }
  CFRelease(mouseEventTap);
  
  [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}

@end
