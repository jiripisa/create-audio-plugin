// {{APP}}AU.h - identity of the {{APP}} Audio Unit.
//
// These four-character codes are permanent: hosts find the plug-in and its saved state by them.
// They must match the AudioComponents entry in Resources/AudioUnit-Info.plist.

#ifndef {{APP_UPPER}}_AU_H
#define {{APP_UPPER}}_AU_H

#define {{APP_UPPER}}_AU_TYPE          'aumu'   // music device (instrument)
#define {{APP_UPPER}}_AU_SUBTYPE       '{{AU_SUBTYPE}}'
#define {{APP_UPPER}}_AU_MANUFACTURER  'JPis'

// The component bundle's identifier (CFBundleIdentifier in Resources/AudioUnit-Info.plist) and the
// class in it that makes the plug-in's window.
#define {{APP_UPPER}}_AU_BUNDLE_ID     "{{BUNDLE_ID}}.audiounit"
#define {{APP_UPPER}}_AU_VIEW_CLASS    "{{APP}}AUViewFactory"

#include <AudioToolbox/AudioToolbox.h>

// Properties of the unit beyond Apple's, for its own window (global scope).
//   Engine:       read only. The unit's {{APP}}Engine* (size: one pointer). The window reads and
//                 sets what is not an Audio Unit parameter through it (the pads, their notes and
//                 groups, the mode) and plays its on-screen keys and pads. The engine lives as
//                 long as the unit.
//   StateChanged: write only, any UInt32. The window sets it after it changed the pads or the
//                 mode through the engine; the unit then tells the host its saved state
//                 (kAudioUnitProperty_ClassInfo) changed, so that the project is marked edited.
//   SelectedPad:  read/write UInt32, 0...15. The pad the window shows, so that it reopens on it;
//                 saved with the unit's state. Any other value, or another size, is refused
//                 (kAudioUnitErr_InvalidPropertyValue).
//   PresetNames:  read/write CFArrayRef of 17 CFStrings: the preset each set came from, the
//                 keyboard set's first, then pad 1...16's; "" for none. The engine does not hold
//                 them: the window sets them, the unit keeps a copy and saves it with its state.
//                 An array of another length or with anything but strings in it is refused
//                 (kAudioUnitErr_InvalidPropertyValue); a name longer than a preset's (60
//                 characters) counts as none. As for every CF-typed property, a get hands the
//                 array over retained (+1): the caller releases it. The window uses it from the
//                 main thread; the unit guards it with a lock of its own, since a host saves and
//                 restores the state, names included, on a thread of its choosing.
enum
{
    k{{APP}}Property_Engine       = 64001,
    k{{APP}}Property_StateChanged = 64002,
    k{{APP}}Property_SelectedPad  = 64003,
    k{{APP}}Property_PresetNames  = 64004
};

#ifdef __cplusplus
extern "C" {
#endif

// The factory function a host looks up by name (AudioUnit-Info.plist, factoryFunction). It is
// defined by AUSDK_COMPONENT_ENTRY in {{APP}}AU.cpp; declared here for code that registers the
// Audio Unit with its own process, as the tests do.
void* {{APP}}AUFactory(const AudioComponentDescription* inDesc);

#ifdef __cplusplus
}
#endif

#endif // {{APP_UPPER}}_AU_H
