//
//  main.m
//  MouseNav
//
//  Created by George MacKerron on 17/03/2021.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    NSApplication *application = NSApplication.sharedApplication;
    application.delegate = AppDelegate.new;
    [application run];
  }
  return NSApplicationMain(argc, argv);
}
