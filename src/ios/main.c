#include <loop.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "log.h"

void platformLog(const logType type, const char *format, va_list va) {
    const char* textPrefix = "";
    switch (type) {
        case LOG_TYPE_NORMAL:  break;
        case LOG_TYPE_WARNING: textPrefix = "Warning: "; break;
        case LOG_TYPE_ERROR:   textPrefix = "Error: "; break;
        case LOG_TYPE_DEBUG:   textPrefix = "Debug: "; break;
    }
    fputs(textPrefix, stderr);
    vfprintf(stderr, format, va);
}

int main(int argc, char* argv[]) {
    (void)argc;
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    // Hide the home indicator and require a second swipe for system gestures, so swiping on the D-pad doesn't leave the game
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    // Touches are handled by the on-screen controls, don't also turn them into mouse clicks
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");

    // data.win and the external music .ogg files are copied into the root of the .app bundle
    static char dataWinPath[1024];
    snprintf(dataWinPath, sizeof(dataWinPath), "%sdata.win", SDL_GetBasePath());

    // Saves go to the app's Documents folder, which is exposed in the Files app so saves can be copied to/from a PC
    static char saveFolder[1024];
    const char* documents = SDL_GetUserFolder(SDL_FOLDER_DOCUMENTS);
    if (documents == NULL) {
        logError("Could not resolve the Documents folder: %s\n", SDL_GetError());
        return 1;
    }
    snprintf(saveFolder, sizeof(saveFolder), "%s", documents);
    mkdir(saveFolder, 0755);

    CommandLineArgs args = {0};

    args.exitAtFrame = -1;
#ifdef ENABLE_VM_TRACING
    args.traceBytecodeAfterFrame = 0;
#endif
    args.speedMultiplier = 1.0;
    args.fastForwardSpeed = 0.0;
    args.osType = OS_WINDOWS;
    args.profilerFramesBetween = 0;
    args.loadType = DATAWINLOADTYPE_LOAD_IN_MEMORY_AHEAD_OF_TIME;
    args.renderer = MODERN_GL;
    args.dataWinPath = dataWinPath;
    args.saveFolder = saveFolder;

    int ret = loop(args, argv[0]);
    freeCommandLineArgs(&args);
    return ret;
}
