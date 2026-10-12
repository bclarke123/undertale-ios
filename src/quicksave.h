#ifndef _BS_QUICKSAVE_H_
#define _BS_QUICKSAVE_H_

#include "runner.h"

typedef enum {
    QUICKSAVE_SAVED,
    QUICKSAVE_UNSUPPORTED, // not Undertale (no scr_save / obj_mainchara)
    QUICKSAVE_BUSY,        // not in the overworld with free movement (battle, cutscene, dialogue, menu)
} QuickSaveResult;

// Undertale "save anywhere": runs the game's own scr_save, exactly like touching a save point, but from wherever the player is.
// Only allowed while the player is walking around freely, since that's the only state a save point can be used in.
// Must be called between frames (not while the VM is executing).
QuickSaveResult QuickSave_undertale(Runner* runner);

typedef enum {
    QUICKLOAD_LOADED,
    QUICKLOAD_UNSUPPORTED, // not Undertale
    QUICKLOAD_NO_SAVE,     // no file0 yet
    QUICKLOAD_BUSY,        // still on the title/naming screens, where the menu's own Continue should be used
} QuickLoadResult;

// Undertale "load anywhere": does what the title screen's Continue does (stop all audio, run scr_load, which reads file0
// and room_goto()s the saved room), from wherever the player is, including battles and cutscenes.
// Must be called between frames (not while the VM is executing).
QuickLoadResult QuickLoad_undertale(Runner* runner);

#endif
