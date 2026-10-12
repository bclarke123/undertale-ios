#ifndef _BS_IOS_TOUCH_OVERLAY_H_
#define _BS_IOS_TOUCH_OVERLAY_H_

#include <stdbool.h>
#include <stdint.h>

typedef void (*TouchOverlayKeyCallback)(int32_t gmlKey);

// Installs an on-screen D-pad + Z/X/C buttons on top of the given UIWindow (SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER).
// The callbacks are invoked on the main thread while SDL pumps events, so they can safely touch the runner state.
void TouchOverlay_install(void* uiWindow, TouchOverlayKeyCallback onKeyDown, TouchOverlayKeyCallback onKeyUp);

// Hides the overlay (releasing any held keys), e.g. while a game controller is connected.
void TouchOverlay_setVisible(bool visible);

// Briefly shows a message at the top of the screen, even while the overlay itself is hidden.
void TouchOverlay_showMessage(const char* message);

#endif
