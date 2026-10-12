#import <UIKit/UIKit.h>
#include <math.h>

#include "touch_overlay.h"
#include "runner_keyboard.h"

// Undertale's controls: arrows to move, Z/Enter confirm, X/Shift cancel, C/Ctrl menu
enum {
    OVERLAY_KEY_UP,
    OVERLAY_KEY_DOWN,
    OVERLAY_KEY_LEFT,
    OVERLAY_KEY_RIGHT,
    OVERLAY_KEY_Z,
    OVERLAY_KEY_X,
    OVERLAY_KEY_C,
    OVERLAY_KEY_SAVE,
    OVERLAY_KEY_COUNT
};

static const int32_t OVERLAY_TO_GML_KEY[OVERLAY_KEY_COUNT] = {
    [OVERLAY_KEY_UP]    = VK_UP,
    [OVERLAY_KEY_DOWN]  = VK_DOWN,
    [OVERLAY_KEY_LEFT]  = VK_LEFT,
    [OVERLAY_KEY_RIGHT] = VK_RIGHT,
    [OVERLAY_KEY_Z]     = 'Z',
    [OVERLAY_KEY_X]     = 'X',
    [OVERLAY_KEY_C]     = 'C',
    [OVERLAY_KEY_SAVE]  = VK_F7, // quick save, see quicksave.c
};

// Loading throws away unsaved progress, so the LOAD button has to be held this long before it fires
static const CFTimeInterval LOAD_HOLD_SECONDS = 1.0;

static TouchOverlayKeyCallback g_onKeyDown;
static TouchOverlayKeyCallback g_onKeyUp;

@interface BSTouchOverlayView : UIView
- (void)setLoadHeld:(bool)held;
@end

@implementation BSTouchOverlayView {
    CGPoint _dpadCenter;
    CGFloat _dpadRadius;
    CGPoint _buttonCenters[3]; // Z, X, C
    CGFloat _buttonRadius;

    CAShapeLayer* _dpadBase;
    CAShapeLayer* _dpadArrows[4]; // up, down, left, right
    CAShapeLayer* _buttonLayers[3];
    CATextLayer* _buttonLabels[3];
    CGRect _saveRect;
    CAShapeLayer* _saveLayer;
    CATextLayer* _saveLabel;

    CGRect _loadRect;
    CAShapeLayer* _loadLayer;
    CAShapeLayer* _loadProgressLayer;
    CATextLayer* _loadLabel;
    bool _loadHeld;
    bool _loadFired;
    CFTimeInterval _loadStart;
    NSTimer* _loadTimer;

    bool _held[OVERLAY_KEY_COUNT];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _dpadBase = [self makeShapeLayer];
        for (int i = 0; i < 4; i++) _dpadArrows[i] = [self makeShapeLayer];

        NSArray<NSString*>* labels = @[@"Z", @"X", @"C"];
        for (int i = 0; i < 3; i++) {
            _buttonLayers[i] = [self makeShapeLayer];
            CATextLayer* text = [CATextLayer layer];
            text.string = labels[i];
            text.alignmentMode = kCAAlignmentCenter;
            text.foregroundColor = [UIColor colorWithWhite:1.0 alpha:0.7].CGColor;
            text.contentsScale = UIScreen.mainScreen.scale;
            [self.layer addSublayer:text];
            _buttonLabels[i] = text;
        }

        _saveLayer = [self makeShapeLayer];
        _saveLabel = [self makePillLabel:@"SAVE"];

        _loadLayer = [self makeShapeLayer];
        _loadProgressLayer = [CAShapeLayer layer];
        _loadProgressLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
        [self.layer addSublayer:_loadProgressLayer];
        _loadLabel = [self makePillLabel:@"LOAD"];
    }
    return self;
}

- (CATextLayer*)makePillLabel:(NSString*)text {
    CATextLayer* label = [CATextLayer layer];
    label.string = text;
    label.alignmentMode = kCAAlignmentCenter;
    label.foregroundColor = [UIColor colorWithWhite:1.0 alpha:0.7].CGColor;
    label.contentsScale = UIScreen.mainScreen.scale;
    [self.layer addSublayer:label];
    return label;
}

- (CAShapeLayer*)makeShapeLayer {
    CAShapeLayer* layer = [CAShapeLayer layer];
    layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    layer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.25].CGColor;
    layer.lineWidth = 2.0;
    [self.layer addSublayer:layer];
    return layer;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    CGFloat unit = MIN(safe.size.width, safe.size.height);
    CGFloat margin = unit * 0.06;

    // The game is 4:3 and letterboxed, so on wider screens the controls fit in the black side bars instead of covering the game
    CGFloat sideBar = (self.bounds.size.width - self.bounds.size.height * 4.0 / 3.0) / 2.0;
    bool fitsInBars = sideBar >= unit * 0.2;

    _dpadRadius = fitsInBars ? MIN(unit * 0.16, sideBar * 0.42) : unit * 0.16;
    _buttonRadius = fitsInBars ? MIN(unit * 0.065, sideBar * 0.17) : unit * 0.065;
    CGFloat spacing = _buttonRadius * 2.6;

    if (fitsInBars) {
        CGFloat leftBarCenter = CGRectGetMinX(self.bounds) + sideBar / 2.0;
        CGFloat rightBarCenter = CGRectGetMaxX(self.bounds) - sideBar / 2.0;
        _dpadCenter = CGPointMake(MAX(leftBarCenter, CGRectGetMinX(safe) + _dpadRadius), CGRectGetMaxY(safe) - margin - _dpadRadius);
        // Triangle of buttons centred in the right bar: Z bottom-right, X bottom-left, C on top
        CGFloat cx = MIN(rightBarCenter, CGRectGetMaxX(safe) - spacing / 2.0 - _buttonRadius);
        CGFloat bottomY = CGRectGetMaxY(safe) - margin - _buttonRadius;
        _buttonCenters[0] = CGPointMake(cx + spacing / 2.0, bottomY - spacing * 0.45);
        _buttonCenters[1] = CGPointMake(cx - spacing / 2.0, bottomY);
        _buttonCenters[2] = CGPointMake(cx, bottomY - spacing * 1.35);
    } else {
        _dpadCenter = CGPointMake(CGRectGetMinX(safe) + margin + _dpadRadius, CGRectGetMaxY(safe) - margin - _dpadRadius);
        // Z is the primary button, so it sits closest to the thumb's resting spot; X to its left, C above
        CGPoint anchor = CGPointMake(CGRectGetMaxX(safe) - margin - _buttonRadius, CGRectGetMaxY(safe) - margin - _buttonRadius * 2.0);
        _buttonCenters[0] = anchor;
        _buttonCenters[1] = CGPointMake(anchor.x - spacing, anchor.y + spacing * 0.45);
        _buttonCenters[2] = CGPointMake(anchor.x - spacing * 0.35, anchor.y - spacing);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _dpadBase.path = [UIBezierPath bezierPathWithArcCenter:_dpadCenter radius:_dpadRadius startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;

    // Directions: up, down, left, right as angles in UIKit coordinates (y grows downwards)
    const CGFloat angles[4] = { -M_PI_2, M_PI_2, M_PI, 0 };
    for (int i = 0; i < 4; i++) {
        CGFloat tipDist = _dpadRadius * 0.82;
        CGFloat baseDist = _dpadRadius * 0.45;
        CGFloat halfWidth = _dpadRadius * 0.22;
        CGFloat a = angles[i];
        CGPoint dir = CGPointMake(cos(a), sin(a));
        CGPoint perp = CGPointMake(-dir.y, dir.x);

        UIBezierPath* arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake(_dpadCenter.x + dir.x * tipDist, _dpadCenter.y + dir.y * tipDist)];
        [arrow addLineToPoint:CGPointMake(_dpadCenter.x + dir.x * baseDist + perp.x * halfWidth, _dpadCenter.y + dir.y * baseDist + perp.y * halfWidth)];
        [arrow addLineToPoint:CGPointMake(_dpadCenter.x + dir.x * baseDist - perp.x * halfWidth, _dpadCenter.y + dir.y * baseDist - perp.y * halfWidth)];
        [arrow closePath];
        _dpadArrows[i].path = arrow.CGPath;
    }

    UIFont* font = [UIFont monospacedSystemFontOfSize:_buttonRadius * 0.9 weight:UIFontWeightBold];
    for (int i = 0; i < 3; i++) {
        _buttonLayers[i].path = [UIBezierPath bezierPathWithArcCenter:_buttonCenters[i] radius:_buttonRadius startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
        _buttonLabels[i].font = (__bridge CFTypeRef)font;
        _buttonLabels[i].fontSize = font.pointSize;
        CGFloat h = font.lineHeight;
        _buttonLabels[i].frame = CGRectMake(_buttonCenters[i].x - _buttonRadius, _buttonCenters[i].y - h / 2, _buttonRadius * 2, h);
    }

    // Small pill in the top-right corner, out of the way of the thumbs
    CGFloat saveW = unit * 0.11, saveH = unit * 0.05;
    _saveRect = CGRectMake(CGRectGetMaxX(safe) - margin * 0.5 - saveW, CGRectGetMinY(safe) + margin * 0.5, saveW, saveH);
    _saveLayer.path = [UIBezierPath bezierPathWithRoundedRect:_saveRect cornerRadius:saveH / 2].CGPath;
    UIFont* saveFont = [UIFont monospacedSystemFontOfSize:saveH * 0.45 weight:UIFontWeightBold];
    _saveLabel.font = (__bridge CFTypeRef)saveFont;
    _saveLabel.fontSize = saveFont.pointSize;
    _saveLabel.frame = CGRectMake(_saveRect.origin.x, CGRectGetMidY(_saveRect) - saveFont.lineHeight / 2, saveW, saveFont.lineHeight);

    // LOAD sits just left of SAVE
    _loadRect = CGRectOffset(_saveRect, -(saveW + margin * 0.5), 0);
    _loadLayer.path = [UIBezierPath bezierPathWithRoundedRect:_loadRect cornerRadius:saveH / 2].CGPath;
    _loadLabel.font = (__bridge CFTypeRef)saveFont;
    _loadLabel.fontSize = saveFont.pointSize;
    _loadLabel.frame = CGRectOffset(_saveLabel.frame, _loadRect.origin.x - _saveRect.origin.x, 0);
    [self updateLoadProgress:0];

    [CATransaction commit];
}

// Adds the keys a single touch at `p` is pressing into `pressed`
- (void)collectKeysForPoint:(CGPoint)p into:(bool*)pressed {
    if (CGRectContainsPoint(CGRectInset(_saveRect, -12, -12), p)) {
        pressed[OVERLAY_KEY_SAVE] = true;
        return;
    }

    CGFloat dx = p.x - _dpadCenter.x;
    CGFloat dy = p.y - _dpadCenter.y;
    CGFloat dist = hypot(dx, dy);
    // The D-pad's hit area is larger than what's drawn so thumbs drifting off the edge keep moving
    if (dist <= _dpadRadius * 1.5) {
        if (dist < _dpadRadius * 0.2) return; // dead zone
        // 8-way: each axis engages within 67.5 degrees of its direction, so diagonals overlap both
        CGFloat angle = atan2(dy, dx);
        const CGFloat reach = M_PI * 3.0 / 8.0;
        if (fabs(angle) < reach) pressed[OVERLAY_KEY_RIGHT] = true;
        if (fabs(angle) > M_PI - reach) pressed[OVERLAY_KEY_LEFT] = true;
        if (fabs(angle + M_PI_2) < reach) pressed[OVERLAY_KEY_UP] = true;
        if (fabs(angle - M_PI_2) < reach) pressed[OVERLAY_KEY_DOWN] = true;
        return;
    }

    int nearest = -1;
    CGFloat nearestDist = _buttonRadius * 1.35;
    for (int i = 0; i < 3; i++) {
        CGFloat d = hypot(p.x - _buttonCenters[i].x, p.y - _buttonCenters[i].y);
        if (d < nearestDist) {
            nearestDist = d;
            nearest = i;
        }
    }
    if (nearest >= 0) pressed[OVERLAY_KEY_Z + nearest] = true;
}

- (void)applyPressed:(const bool*)pressed {
    for (int k = 0; k < OVERLAY_KEY_COUNT; k++) {
        if (pressed[k] == _held[k]) continue;
        _held[k] = pressed[k];
        if (pressed[k]) {
            if (g_onKeyDown) g_onKeyDown(OVERLAY_TO_GML_KEY[k]);
        } else {
            if (g_onKeyUp) g_onKeyUp(OVERLAY_TO_GML_KEY[k]);
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGColorRef idle = [UIColor colorWithWhite:0.0 alpha:0.25].CGColor;
    CGColorRef active = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    for (int i = 0; i < 4; i++) _dpadArrows[i].fillColor = _held[OVERLAY_KEY_UP + i] ? active : idle;
    for (int i = 0; i < 3; i++) _buttonLayers[i].fillColor = _held[OVERLAY_KEY_Z + i] ? active : idle;
    _saveLayer.fillColor = _held[OVERLAY_KEY_SAVE] ? active : idle;
    [CATransaction commit];
}

// Recomputes the full key state from every touch still on screen, so sliding between buttons and multi-touch just work
- (void)refreshWithEvent:(UIEvent*)event {
    bool pressed[OVERLAY_KEY_COUNT] = {0};
    bool loadTouched = false;
    for (UITouch* touch in [event touchesForView:self]) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) continue;
        CGPoint p = [touch locationInView:self];
        if (CGRectContainsPoint(CGRectInset(_loadRect, -12, -12), p)) {
            loadTouched = true;
            continue;
        }
        [self collectKeysForPoint:p into:pressed];
    }
    [self applyPressed:pressed];
    [self setLoadHeld:loadTouched];
}

- (void)releaseAll {
    bool pressed[OVERLAY_KEY_COUNT] = {0};
    [self applyPressed:pressed];
    [self setLoadHeld:false];
}

// ===[ Hold-to-load ]===

- (void)setLoadHeld:(bool)held {
    if (held == _loadHeld) return;
    _loadHeld = held;

    if (held) {
        _loadFired = false;
        _loadStart = CACurrentMediaTime();
        // Runs on the main run loop, which SDL keeps pumping every frame
        _loadTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(loadTick) userInfo:nil repeats:YES];
    } else {
        [_loadTimer invalidate];
        _loadTimer = nil;
        if (_loadFired && g_onKeyUp) g_onKeyUp(VK_F9);
        _loadFired = false;
        [self updateLoadProgress:0];
    }
}

- (void)loadTick {
    CGFloat progress = MIN(1.0, (CACurrentMediaTime() - _loadStart) / LOAD_HOLD_SECONDS);
    [self updateLoadProgress:progress];
    if (progress >= 1.0 && !_loadFired) {
        _loadFired = true; // only once per hold; released in setLoadHeld
        if (g_onKeyDown) g_onKeyDown(VK_F9); // quick load, see quicksave.c
    }
}

// Fills the LOAD pill from left to right as it's held
- (void)updateLoadProgress:(CGFloat)progress {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (progress <= 0) {
        _loadProgressLayer.path = nil;
    } else {
        UIBezierPath* pill = [UIBezierPath bezierPathWithRoundedRect:_loadRect cornerRadius:_loadRect.size.height / 2];
        CAShapeLayer* mask = [CAShapeLayer layer];
        mask.path = [UIBezierPath bezierPathWithRect:CGRectMake(_loadRect.origin.x, _loadRect.origin.y, _loadRect.size.width * progress, _loadRect.size.height)].CGPath;
        _loadProgressLayer.path = pill.CGPath;
        _loadProgressLayer.mask = mask;
    }
    [CATransaction commit];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self refreshWithEvent:event]; }
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self refreshWithEvent:event]; }
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self refreshWithEvent:event]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self refreshWithEvent:event]; }

@end

static BSTouchOverlayView* g_overlay;
static UILabel* g_messageLabel;

void TouchOverlay_install(void* uiWindow, TouchOverlayKeyCallback onKeyDown, TouchOverlayKeyCallback onKeyUp) {
    g_onKeyDown = onKeyDown;
    g_onKeyUp = onKeyUp;

    UIWindow* window = (__bridge UIWindow*)uiWindow;
    UIView* host = window.rootViewController.view ?: window;
    g_overlay = [[BSTouchOverlayView alloc] initWithFrame:host.bounds];
    [host addSubview:g_overlay];

    // Separate from the overlay so messages still show while a controller is connected and the overlay is hidden
    g_messageLabel = [[UILabel alloc] init];
    g_messageLabel.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightBold];
    g_messageLabel.textColor = UIColor.whiteColor;
    g_messageLabel.textAlignment = NSTextAlignmentCenter;
    g_messageLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    g_messageLabel.layer.cornerRadius = 8;
    g_messageLabel.clipsToBounds = YES;
    g_messageLabel.hidden = YES;
    g_messageLabel.userInteractionEnabled = NO;
    [host addSubview:g_messageLabel];

    // Launch with "-BSTestLoadHold YES" to hold the LOAD button for 1.5s without touching the screen
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"BSTestLoadHold"]) {
        BSTouchOverlayView* overlay = g_overlay;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [overlay setLoadHeld:true];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [overlay setLoadHeld:false];
        });
    }

    // Launch with "-BSTestMessage YES" to check the message rendering without needing to save
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"BSTestMessage"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            TouchOverlay_showMessage("Game saved");
        });
    }
}

void TouchOverlay_showMessage(const char* message) {
    if (!g_messageLabel) return;
    static NSUInteger generation = 0;
    NSUInteger current = ++generation;

    // Sized and placed by hand (top-left corner, inside the safe area; the SAVE button owns the top-right) every time it's shown
    UIView* host = g_messageLabel.superview;
    g_messageLabel.text = [NSString stringWithUTF8String:message];
    CGSize textSize = [g_messageLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGSize size = CGSizeMake(textSize.width + 28, textSize.height + 16);
    CGRect safe = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
    g_messageLabel.frame = CGRectMake(CGRectGetMinX(safe) + 16, CGRectGetMinY(safe) + 16, size.width, size.height);

    [host bringSubviewToFront:g_messageLabel];
    g_messageLabel.alpha = 1;
    g_messageLabel.hidden = NO;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (current != generation) return; // a newer message replaced this one
        g_messageLabel.hidden = YES;
    });
}

void TouchOverlay_setVisible(bool visible) {
    if (!g_overlay || g_overlay.hidden == !visible) return;
    if (!visible) [g_overlay releaseAll];
    g_overlay.hidden = !visible;
}
