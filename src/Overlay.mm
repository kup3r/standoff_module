#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "Runtime.hpp"

static glow::Runtime runtime;
static UIColor* mint(){return [UIColor colorWithRed:.30 green:.98 blue:.80 alpha:1];}
static UIColor* violet(){return [UIColor colorWithRed:.65 green:.47 blue:1 alpha:1];}

@interface GlowCanvas : UIView
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL corners;
@property(nonatomic) BOOL distanceLabels;
@property(nonatomic) BOOL halo;
- (void)refresh;
@end
@implementation GlowCanvas {
    std::vector<glow::Target> targets;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.clearColor;self.userInteractionEnabled=NO;self.corners=YES;self.distanceLabels=YES;self.halo=YES;}return self;
}
- (void)refresh {
    if(self.enabled)runtime.sample(self.bounds.size.width,self.bounds.size.height,targets);
    else targets.clear();
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext();if(!c)return;
    for(const auto& t:targets){
        CGRect box=CGRectMake(t.x,t.y,t.w,t.h);
        UIBezierPath* p=[UIBezierPath bezierPath];
        CGFloat a=MIN(t.w*.28,18),b=MIN(t.h*.15,18);
        if(self.corners){
            for(int side=0;side<2;side++)for(int top=0;top<2;top++){
                CGFloat x=side?CGRectGetMaxX(box):box.origin.x;
                CGFloat y=top?CGRectGetMaxY(box):box.origin.y;
                [p moveToPoint:CGPointMake(x+(side?-a:a),y)];[p addLineToPoint:CGPointMake(x,y)];[p addLineToPoint:CGPointMake(x,y+(top?-b:b))];
            }
        }else p=[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:5];
        CGContextSaveGState(c);
        [UIColor.blackColor setStroke];p.lineWidth=4;[p stroke];
        if(self.halo)CGContextSetShadowWithColor(c,CGSizeZero,7,mint().CGColor);
        [mint() setStroke];p.lineWidth=1.5;[p stroke];
        CGContextRestoreGState(c);
        if(self.distanceLabels&&t.distance>=0){
            NSString* text=[NSString stringWithFormat:@"%.0f m",t.distance];
            NSDictionary* attrs=@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor};
            CGSize s=[text sizeWithAttributes:attrs];CGRect r=CGRectMake(t.x+(t.w-s.width)/2-6,t.y+t.h+5,s.width+12,s.height+6);
            [[UIColor colorWithRed:.035 green:.045 blue:.075 alpha:.86] setFill];[[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:5] fill];
            [text drawAtPoint:CGPointMake(r.origin.x+6,r.origin.y+3) withAttributes:attrs];
        }
    }
}
@end

@interface GlowController : UIViewController
@property(nonatomic,strong) GlowCanvas* canvas;
@property(nonatomic,strong) UIButton* bubble;
@property(nonatomic,strong) UIVisualEffectView* panel;
@property(nonatomic,strong) UILabel* status;
@property(nonatomic,strong) CADisplayLink* displayLink;
@end
@interface GlowWindow : UIWindow
@property(nonatomic,weak) GlowController* controller;
@end
@implementation GlowWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    GlowController* c=self.controller;
    if(!c)return NO;
    if(CGRectContainsPoint(c.bubble.frame,point))return YES;
    return !c.panel.hidden&&CGRectContainsPoint(c.panel.frame,point);
}
- (BOOL)canBecomeKeyWindow{return NO;}
@end

@implementation GlowController {
    CFTimeInterval previous;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;
    self.canvas=[[GlowCanvas alloc] initWithFrame:self.view.bounds];self.canvas.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.view addSubview:self.canvas];
    self.bubble=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.bubble setTitle:@"G" forState:UIControlStateNormal];[self.bubble setTitleColor:mint() forState:UIControlStateNormal];
    self.bubble.titleLabel.font=[UIFont systemFontOfSize:23 weight:UIFontWeightBlack];self.bubble.backgroundColor=[UIColor colorWithWhite:.06 alpha:.9];
    self.bubble.layer.cornerRadius=22;self.bubble.layer.borderWidth=1;self.bubble.layer.borderColor=[mint() colorWithAlphaComponent:.5].CGColor;
    self.bubble.layer.shadowColor=mint().CGColor;self.bubble.layer.shadowOpacity=.3;self.bubble.layer.shadowRadius=12;
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:self.bubble];
    self.panel=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    self.panel.layer.cornerRadius=20;self.panel.clipsToBounds=YES;self.panel.layer.borderWidth=1;self.panel.layer.borderColor=[UIColor colorWithWhite:1 alpha:.12].CGColor;[self.view addSubview:self.panel];
    UIStackView* stack=[[UIStackView alloc] init];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.panel.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.panel.contentView.leadingAnchor constant:18],[stack.trailingAnchor constraintEqualToAnchor:self.panel.contentView.trailingAnchor constant:-18],[stack.topAnchor constraintEqualToAnchor:self.panel.contentView.topAnchor constant:18],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.panel.contentView.bottomAnchor constant:-12]]];
    UILabel* title=[self label:@"GLOW   /   RESEARCH BUILD" size:15 color:mint()];title.font=[UIFont systemFontOfSize:15 weight:UIFontWeightHeavy];[stack addArrangedSubview:title];
    [self row:@"ESP · кандидаты" tag:1 enabled:NO stack:stack];
    [self row:@"Угловые рамки" tag:2 enabled:YES stack:stack];
    [self row:@"Мягкое свечение" tag:3 enabled:YES stack:stack];
    [self row:@"Расстояние" tag:4 enabled:YES stack:stack];
    [self row:@"Тонировка моделей · эксперимент" tag:5 enabled:NO stack:stack];
    UILabel* skins=[self label:@"Скинченджер: игровые методы ещё не сопоставлены" size:11 color:[UIColor colorWithWhite:.7 alpha:1]];skins.numberOfLines=0;[stack addArrangedSubview:skins];
    self.status=[self label:@"Открой матч, затем включи ESP. Команды и HP не сопоставлены." size:10 color:[UIColor colorWithWhite:.6 alpha:1]];self.status.numberOfLines=0;[stack addArrangedSubview:self.status];
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];self.displayLink.preferredFramesPerSecond=30;[self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive) name:UIApplicationWillResignActiveNotification object:nil];
}
- (UILabel*)label:(NSString*)text size:(CGFloat)size color:(UIColor*)color {UILabel* l=[[UILabel alloc] init];l.text=text;l.font=[UIFont systemFontOfSize:size weight:UIFontWeightMedium];l.textColor=color;return l;}
- (void)row:(NSString*)name tag:(NSInteger)tag enabled:(BOOL)enabled stack:(UIStackView*)stack {
    UIStackView* row=[[UIStackView alloc] init];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;row.spacing=8;
    UILabel* label=[self label:name size:12 color:UIColor.whiteColor];label.numberOfLines=2;
    UISwitch* toggle=[[UISwitch alloc] init];toggle.tag=tag;toggle.on=enabled;toggle.onTintColor=tag==5?violet():mint();
    [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:label];[row addArrangedSubview:toggle];[stack addArrangedSubview:row];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];UIEdgeInsets safe=self.view.safeAreaInsets;
    self.bubble.frame=CGRectMake(safe.left+12,safe.top+10,44,44);
    CGFloat height=MIN(350,self.view.bounds.size.height-safe.top-safe.bottom-16);
    self.panel.frame=CGRectMake(safe.left+66,safe.top+8,MIN(330,self.view.bounds.size.width-safe.left-safe.right-78),height);
}
- (void)togglePanel{self.panel.hidden=!self.panel.hidden;}
- (void)changed:(UISwitch*)s {
    switch(s.tag){case 1:self.canvas.enabled=s.on;if(!s.on)runtime.restore();break;case 2:self.canvas.corners=s.on;break;case 3:self.canvas.halo=s.on;break;case 4:self.canvas.distanceLabels=s.on;break;case 5:runtime.setTint(s.on);break;}
}
- (void)tick:(CADisplayLink*)link {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(link.timestamp-previous<.1)return;previous=link.timestamp;
    [self.canvas refresh];self.status.text=[NSString stringWithUTF8String:runtime.status.c_str()];
}
- (void)inactive{runtime.restore();}
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskAll;}
@end

static GlowWindow* glowWindow;
static void installOverlay(){
    if(glowWindow)return;
    UIWindowScene* chosen=nil;
    for(UIScene* s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive){chosen=(UIWindowScene*)s;break;}
    if(!chosen)return;
    GlowController* c=[[GlowController alloc] init];glowWindow=[[GlowWindow alloc] initWithWindowScene:chosen];glowWindow.controller=c;glowWindow.rootViewController=c;glowWindow.windowLevel=UIWindowLevelStatusBar+1;glowWindow.backgroundColor=UIColor.clearColor;glowWindow.hidden=NO;
}
__attribute__((constructor)) static void startGlow(){
    dispatch_async(dispatch_get_main_queue(),^{
        [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* n){installOverlay();}];
        installOverlay();
    });
}
