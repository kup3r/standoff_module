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

@interface GlowController : UIViewController <UIGestureRecognizerDelegate>
@property(nonatomic,strong) GlowCanvas* canvas;
@property(nonatomic,strong) UIVisualEffectView* panel;
@property(nonatomic,strong) UILabel* status;
@property(nonatomic,strong) CADisplayLink* displayLink;
@property(nonatomic,strong) NSHashTable<UIWindow*>* gestureWindows;
- (void)attachGestures;
- (void)updateCaptureState;
@end
@interface GlowWindow : UIWindow
@property(nonatomic,weak) GlowController* controller;
@end
@implementation GlowWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    GlowController* c=self.controller;
    if(!c||c.view.hidden)return NO;
    return !c.panel.hidden&&CGRectContainsPoint(c.panel.frame,point);
}
- (BOOL)canBecomeKeyWindow{return NO;}
@end

@implementation GlowController {
    CFTimeInterval previous;
    CFTimeInterval gestureScan;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;
    self.canvas=[[GlowCanvas alloc] initWithFrame:self.view.bounds];self.canvas.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.view addSubview:self.canvas];
    self.gestureWindows=NSHashTable.weakObjectsHashTable;
    self.panel=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    self.panel.hidden=YES;self.panel.layer.cornerRadius=16;self.panel.clipsToBounds=YES;self.panel.layer.borderWidth=1;self.panel.layer.borderColor=[UIColor colorWithWhite:1 alpha:.12].CGColor;[self.view addSubview:self.panel];
    UIScrollView* scroll=[[UIScrollView alloc] init];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.panel.contentView addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.panel.contentView.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.panel.contentView.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:self.panel.contentView.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.panel.contentView.bottomAnchor]]];
    UIStackView* stack=[[UIStackView alloc] init];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-18],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]]];
    UIStackView* header=[[UIStackView alloc] init];header.axis=UILayoutConstraintAxisHorizontal;
    UILabel* title=[self label:@"GLOW" size:16 color:mint()];title.font=[UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];[header addArrangedSubview:title];
    UIButton* close=[UIButton buttonWithType:UIButtonTypeSystem];[close setTitle:@"Закрыть" forState:UIControlStateNormal];[close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];[close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];[header addArrangedSubview:close];[stack addArrangedSubview:header];
    [stack addArrangedSubview:[self label:@"2 касания · 3 пальца" size:10 color:[UIColor colorWithWhite:.65 alpha:1]]];
    [self row:@"ESP · кандидаты" tag:1 enabled:NO stack:stack];
    [self row:@"Угловые рамки" tag:2 enabled:YES stack:stack];
    [self row:@"Мягкое свечение" tag:3 enabled:YES stack:stack];
    [self row:@"Расстояние" tag:4 enabled:YES stack:stack];
    [self row:@"Тонировка моделей · эксперимент" tag:5 enabled:NO stack:stack];
    UILabel* skins=[self label:@"Скинченджер: игровые методы ещё не сопоставлены" size:11 color:[UIColor colorWithWhite:.7 alpha:1]];skins.numberOfLines=0;[stack addArrangedSubview:skins];
    UILabel* recording=[self label:@"При записи меню и эффекты отключаются также на экране телефона." size:10 color:[UIColor colorWithWhite:.65 alpha:1]];recording.numberOfLines=0;[stack addArrangedSubview:recording];
    self.status=[self label:@"Открой матч, затем включи ESP. Команды и HP не сопоставлены." size:10 color:[UIColor colorWithWhite:.6 alpha:1]];self.status.numberOfLines=0;[stack addArrangedSubview:self.status];
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];self.displayLink.preferredFramesPerSecond=30;[self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateCaptureState) name:UIScreenCapturedDidChangeNotification object:nil];
    [self updateCaptureState];
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
    CGFloat height=MIN(390,self.view.bounds.size.height-safe.top-safe.bottom-16);
    CGFloat width=MIN(330,self.view.bounds.size.width-safe.left-safe.right-24);
    self.panel.frame=CGRectMake(safe.left+12,safe.top+8,width,height);
    [self attachGestures];
}
- (void)attachGestures {
    NSArray<UIWindow*>* windows=self.view.window.windowScene?self.view.window.windowScene.windows:UIApplication.sharedApplication.windows;
    for(UIWindow* window in windows){
        if([self.gestureWindows containsObject:window])continue;
        UITapGestureRecognizer* tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(menuGesture:)];
        tap.numberOfTouchesRequired=3;tap.numberOfTapsRequired=2;tap.cancelsTouchesInView=NO;tap.delaysTouchesBegan=NO;tap.delaysTouchesEnded=NO;tap.delegate=self;
        [window addGestureRecognizer:tap];[self.gestureWindows addObject:window];
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)other{return YES;}
- (void)menuGesture:(UITapGestureRecognizer*)gesture {if(gesture.state==UIGestureRecognizerStateRecognized)[self togglePanel];}
- (void)togglePanel{[self updateCaptureState];if(!self.view.hidden)self.panel.hidden=!self.panel.hidden;}
- (void)updateCaptureState {
    UIWindowScene* scene=self.view.window.windowScene;
    UIScreen* screen=scene?scene.screen:UIScreen.mainScreen;
    BOOL captured=screen.isCaptured;
    if(@available(iOS 17.0,*)){if(scene)captured=captured||(scene.traitCollection.sceneCaptureState==UISceneCaptureStateActive);}
    BOOL active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    runtime.setVisualsAllowed(self.view.window&&active&&!captured);
    self.view.hidden=captured||!active;
}
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {[super traitCollectionDidChange:previousTraitCollection];[self updateCaptureState];}
- (void)changed:(UISwitch*)s {
    switch(s.tag){case 1:self.canvas.enabled=s.on;if(!s.on)runtime.restore();break;case 2:self.canvas.corners=s.on;break;case 3:self.canvas.halo=s.on;break;case 4:self.canvas.distanceLabels=s.on;break;case 5:runtime.setTint(s.on);break;}
}
- (void)tick:(CADisplayLink*)link {
    [self updateCaptureState];
    if(link.timestamp-gestureScan>1){gestureScan=link.timestamp;[self attachGestures];}
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(self.view.hidden)return;
    if(link.timestamp-previous<.1)return;previous=link.timestamp;
    [self.canvas refresh];self.status.text=[NSString stringWithUTF8String:runtime.status.c_str()];
}
- (void)inactive{runtime.setVisualsAllowed(false);self.view.hidden=YES;}
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskAll;}
@end

static GlowWindow* glowWindow;
static void installOverlay(){
    if(glowWindow)return;
    UIWindowScene* chosen=nil;
    for(UIScene* s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive){chosen=(UIWindowScene*)s;break;}
    UIWindow* host=nil;
    for(UIWindow* window in UIApplication.sharedApplication.windows)if(window.isKeyWindow){host=window;break;}
    if(!chosen&&!host)return;
    GlowController* c=[[GlowController alloc] init];
    glowWindow=chosen?[[GlowWindow alloc] initWithWindowScene:chosen]:[[GlowWindow alloc] initWithFrame:host.frame];
    glowWindow.controller=c;glowWindow.rootViewController=c;glowWindow.windowLevel=UIWindowLevelStatusBar+1;glowWindow.backgroundColor=UIColor.clearColor;glowWindow.hidden=NO;
}
__attribute__((constructor)) static void startGlow(){
    dispatch_async(dispatch_get_main_queue(),^{
        [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* n){installOverlay();}];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* n){installOverlay();}];
        installOverlay();
    });
}
