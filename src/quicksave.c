#include "quicksave.h"

#include <string.h>

#include "log.h"
#include "stb_ds.h"
#include "vm.h"

static int32_t findScriptCodeId(DataWin* dataWin, const char* name) {
    repeat(dataWin->scpt.count, i) {
        Script* script = &dataWin->scpt.scripts[i];
        if (script->present && script->name != nullptr && strcmp(script->name, name) == 0) return script->codeId;
    }
    return -1;
}

static int32_t findObjectIndex(DataWin* dataWin, const char* name) {
    repeat(dataWin->objt.count, i) {
        GameObject* object = &dataWin->objt.objects[i];
        if (object->present && object->name != nullptr && strcmp(object->name, name) == 0) return (int32_t) i;
    }
    return -1;
}

static Instance* findLiveInstance(Runner* runner, int32_t objectIndex) {
    repeat(arrlen(runner->instances), i) {
        Instance* inst = runner->instances[i];
        if (inst->objectIndex == objectIndex && inst->active && !inst->destroyed) return inst;
    }
    return nullptr;
}

static int32_t findRoomIndex(DataWin* dataWin, const char* name) {
    repeat(dataWin->room.count, i) {
        Room* room = &dataWin->room.rooms[i];
        if (room->name != nullptr && strcmp(room->name, name) == 0) return (int32_t) i;
    }
    return -1;
}

// Calls a builtin (not a GML script) by name, returning its result as a real
static GMLReal callBuiltin(Runner* runner, const char* name, RValue* args, int32_t argCount) {
    BuiltinFunc func = VM_findBuiltin(runner->vmContext, name);
    if (func == nullptr) return 0;
    RValue result = func(runner->vmContext, args, argCount);
    GMLReal real = (result.type == RVALUE_STRING || result.type == RVALUE_UNDEFINED) ? 0 : RValue_toReal(result);
    RValue_free(&result);
    return real;
}

static bool readGlobalReal(Runner* runner, const char* name, GMLReal* out) {
    VMContext* vm = runner->vmContext;
    ptrdiff_t slot = shgeti(vm->varNameMap, (char*) name);
    if (slot < 0) return false;
    RValue value = Instance_getSelfVar(vm->globalScopeInstance, vm->varNameMap[slot].value);
    if (value.type == RVALUE_UNDEFINED || value.type == RVALUE_STRING) return false;
    *out = RValue_toReal(value);
    return true;
}

QuickSaveResult QuickSave_undertale(Runner* runner) {
    DataWin* dataWin = runner->dataWin;

    int32_t saveCodeId = findScriptCodeId(dataWin, "scr_save");
    int32_t mainCharaIndex = findObjectIndex(dataWin, "obj_mainchara");
    if (saveCodeId < 0 || mainCharaIndex < 0) return QUICKSAVE_UNSUPPORTED;

    // obj_mainchara only exists in the overworld (battles happen in their own room), and global.interact is 0 only while
    // the player can walk: dialogue, cutscenes, menus and room transitions all set it to something else
    Instance* player = findLiveInstance(runner, mainCharaIndex);
    GMLReal interact;
    if (player == nullptr || !readGlobalReal(runner, "interact", &interact) || interact != 0) return QUICKSAVE_BUSY;

    // Same as the save point's "Save" option: scr_save writes file0 + undertale.ini (room, LV, time, kills, ...)
    Runner_executeCodeOnInstance(runner, player, saveCodeId);
    logInfo("QuickSave: saved in room %d\n", runner->currentRoomIndex);
    return QUICKSAVE_SAVED;
}

QuickLoadResult QuickLoad_undertale(Runner* runner) {
    DataWin* dataWin = runner->dataWin;
    VMContext* vm = runner->vmContext;

    int32_t loadCodeId = findScriptCodeId(dataWin, "scr_load");
    int32_t mainCharaIndex = findObjectIndex(dataWin, "obj_mainchara");
    int32_t timeIndex = findObjectIndex(dataWin, "obj_time");
    int32_t firstGameRoom = findRoomIndex(dataWin, "room_area1");
    if (loadCodeId < 0 || mainCharaIndex < 0 || timeIndex < 0 || firstGameRoom < 0) return QUICKLOAD_UNSUPPORTED;

    // Rooms before the Ruins are the intro, title menu and naming screen
    if (firstGameRoom > runner->currentRoomIndex) return QUICKLOAD_BUSY;

    RValue fileName = RValue_makeString("file0");
    bool hasSave = callBuiltin(runner, "file_exists", &fileName, 1) != 0;
    RValue_free(&fileName);
    if (!hasSave) return QUICKLOAD_NO_SAVE;

    // scr_load only touches globals and self-scratch variables, any instance works as self. obj_mainchara is what the
    // game's own debug-mode "L to load" uses; obj_time is persistent, so it also exists during battles.
    Instance* self = findLiveInstance(runner, mainCharaIndex);
    if (self == nullptr) self = findLiveInstance(runner, timeIndex);
    if (self == nullptr) return QUICKLOAD_BUSY;

    // Same as the title screen's Continue: caster_free(-3), which is audio_stop_all
    callBuiltin(runner, "audio_stop_all", nullptr, 0);

    // Loading from a cutscene/dialogue must not leave the player frozen; the destination room sets it again if it needs to
    ptrdiff_t interactSlot = shgeti(vm->varNameMap, "interact");
    if (interactSlot >= 0) Instance_setSelfVar(vm->globalScopeInstance, vm->varNameMap[interactSlot].value, RValue_makeInt32(0));

    Runner_executeCodeOnInstance(runner, self, loadCodeId);
    logInfo("QuickLoad: loaded from room %d\n", runner->currentRoomIndex);
    return QUICKLOAD_LOADED;
}
