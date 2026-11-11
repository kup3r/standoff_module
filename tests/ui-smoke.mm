#import <UIKit/UIKit.h>

@interface UIViewController (GlowTesting)
- (void)togglePanel;
- (void)attachGestures;
- (void)inactive;
@end

@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow* window;
@end

static void check(BOOL passed,NSString* description,NSMutableArray* failures){if(!passed)[failures addObject:description];}
@implementation SmokeDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[[UIViewController alloc] init];self.window.rootViewController.view.backgroundColor=UIColor.systemBackgroundColor;[self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self runChecks];});return YES;
}
- (void)runChecks {
    NSMutableArray* failures=[NSMutableArray array];UIWindow* overlay=nil;
    for(UIWindow* w in UIApplication.sharedApplication.windows)if([NSStringFromClass(w.class) isEqualToString:@"GlowWindow"]){overlay=w;break;}
    check(overlay!=nil,@"overlay installed in a legacy app",failures);
    if(overlay){
        UIViewController* c=overlay.rootViewController;[c.view layoutIfNeeded];[c attachGestures];
        UIView* panel=[c valueForKey:@"panel"];
        check(panel.hidden,@"menu hidden initially",failures);
        check(!overlay.isKeyWindow,@"game keeps key window",failures);
        BOOL found=NO;
        for(UIGestureRecognizer* gr in self.window.gestureRecognizers)if([gr isKindOfClass:UITapGestureRecognizer.class]){
            UITapGestureRecognizer* tap=(UITapGestureRecognizer*)gr;
            if(tap.numberOfTouchesRequired==3&&tap.numberOfTapsRequired==2){found=YES;check(!tap.cancelsTouchesInView&&!tap.delaysTouchesBegan&&!tap.delaysTouchesEnded,@"gesture preserves game touches",failures);}
        }
        check(found,@"double tap with three fingers registered on game window",failures);
        [c togglePanel];check(!panel.hidden,@"menu opens",failures);
        check([overlay pointInside:CGPointMake(CGRectGetMidX(panel.frame),CGRectGetMidY(panel.frame)) withEvent:nil],@"menu receives touches",failures);
        check(![overlay pointInside:CGPointMake(CGRectGetMaxX(overlay.bounds)-1,CGRectGetMaxY(overlay.bounds)-1) withEvent:nil],@"touches outside menu pass through",failures);
        [c togglePanel];check(panel.hidden,@"menu closes",failures);
        [c inactive];check(c.view.hidden,@"overlay hidden when app resigns active",failures);
    }
    NSString* result=failures.count?[@"FAIL\n" stringByAppendingString:[failures componentsJoinedByString:@"\n"]]:@"PASS: legacy startup, hidden menu, gesture configuration, open/close, touch routing, inactive hiding\n";
    NSURL* documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [result writeToURL:[documents URLByAppendingPathComponent:@"ui-smoke.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"%@",result);
}
@end

int main(int argc,char** argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeDelegate.class));}}
