#+build darwin

package karl2d_darwin_gamecontroller

// CoreHaptics framework bindings for haptic feedback (rumble)
// Based on Apple's CoreHaptics API

import NS "core:sys/darwin/Foundation"

foreign import CoreHaptics "system:CoreHaptics.framework"

// Time constants
TimeImmediate: f64 : 0.0

// Type aliases for framework string constants
EventType :: ^NS.String
EventParameterID :: ^NS.String

// CHHapticEventType constants (NSString* from framework)
@(link_prefix="CHHapticEventType")
	foreign CoreHaptics {
		HapticTransient:   EventType
		HapticContinuous:  EventType
		AudioContinuous:   EventType
		AudioCustom:       EventType
	}

// CHHapticEventParameterID constants (NSString* from framework)
@(link_prefix="CHHapticEventParameterID")
	foreign CoreHaptics {
		HapticIntensity:  EventParameterID
		HapticSharpness:  EventParameterID
		AttackTime:       EventParameterID
		DecayTime:        EventParameterID
		ReleaseTime:      EventParameterID
		Sustained:        EventParameterID
		AudioVolume:      EventParameterID
		AudioPitch:       EventParameterID
		AudioPan:         EventParameterID
		AudioBrightness:  EventParameterID
	}

// CHHapticEngineStoppedReason
EngineStoppedReason :: enum NS.Integer {
	AudioSessionInterrupt    = 1,
	ApplicationSuspended     = 2,
	IdleTimeout              = 3,
	NotifyWhenFinished       = 4,
	EngineDestroyed          = 5,
	GameControllerDisconnect = 6,
	SystemError              = -1,
}

// GCHaptics - for creating haptic engines
@(objc_class="GCHaptics")
Haptics :: struct { using _: NS.Object }

@(objc_type=Haptics, objc_name="createEngineWithLocality")
Haptics_createEngineWithLocality :: proc "c" (
	self: ^Haptics,
	locality: HapticsLocality,
) -> ^HapticEngine {
	return msgSend(^HapticEngine, self, "createEngineWithLocality:", locality)
}

// CHHapticEngine
@(objc_class="CHHapticEngine")
HapticEngine :: struct { using _: NS.Object }

@(objc_type=HapticEngine, objc_name="alloc", objc_is_class_method=true)
HapticEngine_alloc :: proc "c" () -> ^HapticEngine {
	return msgSend(^HapticEngine, HapticEngine, "alloc")
}

@(objc_type=HapticEngine, objc_name="init")
HapticEngine_init :: proc "c" (self: ^HapticEngine) -> ^HapticEngine {
	return msgSend(^HapticEngine, self, "init")
}

@(objc_type=HapticEngine, objc_name="startAndReturnError")
HapticEngine_startAndReturnError :: proc "c" (self: ^HapticEngine, error: ^^NS.Error) -> bool {
	return msgSend(NS.BOOL, self, "startAndReturnError:", error)
}

@(objc_type=HapticEngine, objc_name="startWithCompletionHandler")
HapticEngine_startWithCompletionHandler :: proc "c" (self: ^HapticEngine, handler: rawptr) {
	msgSend(nil, self, "startWithCompletionHandler:", handler)
}

@(objc_type=HapticEngine, objc_name="stopWithCompletionHandler")
HapticEngine_stopWithCompletionHandler :: proc "c" (self: ^HapticEngine, handler: rawptr) {
	msgSend(nil, self, "stopWithCompletionHandler:", handler)
}

@(objc_type=HapticEngine, objc_name="createPlayerWithPattern")
HapticEngine_createPlayerWithPattern :: proc "c" (self: ^HapticEngine, pattern: ^HapticPattern, error: ^^NS.Error) -> ^HapticPatternPlayer {
	return msgSend(^HapticPatternPlayer, self, "createPlayerWithPattern:error:", pattern, error)
}

@(objc_type=HapticEngine, objc_name="setStoppedHandler")
HapticEngine_setStoppedHandler :: proc "c" (self: ^HapticEngine, handler: rawptr) {
	msgSend(nil, self, "setStoppedHandler:", handler)
}

@(objc_type=HapticEngine, objc_name="setResetHandler")
HapticEngine_setResetHandler :: proc "c" (self: ^HapticEngine, handler: rawptr) {
	msgSend(nil, self, "setResetHandler:", handler)
}

// CHHapticPattern
@(objc_class="CHHapticPattern")
	HapticPattern :: struct { using _: NS.Object }

@(objc_type=HapticPattern, objc_name="alloc", objc_is_class_method=true)
HapticPattern_alloc :: proc "c" () -> ^HapticPattern {
	return msgSend(^HapticPattern, HapticPattern, "alloc")
}

@(objc_type=HapticPattern, objc_name="initWithEvents")
HapticPattern_initWithEvents :: proc "c" (
	self: ^HapticPattern,
	events: ^NS.Array,
	parameters: ^NS.Array,
	error: ^^NS.Error,
) -> ^HapticPattern {
	return msgSend(^HapticPattern, self, "initWithEvents:parameters:error:", events,
		parameters, error)
}

// CHHapticEvent
@(objc_class="CHHapticEvent")
	HapticEvent :: struct { using _: NS.Object }

@(objc_type=HapticEvent, objc_name="alloc", objc_is_class_method=true)
HapticEvent_alloc :: proc "c" () -> ^HapticEvent {
	return msgSend(^HapticEvent, HapticEvent, "alloc")
}

@(objc_type=HapticEvent, objc_name="initWithEventType")
HapticEvent_initWithEventType :: proc "c" (
	self: ^HapticEvent,
	event_type: EventType,
	parameters: ^NS.Array,
	relative_time: f64,
	duration: f64,
) -> ^HapticEvent {
	return msgSend(^HapticEvent, self, "initWithEventType:parameters:relativeTime:duration:",
		event_type, parameters, relative_time, duration)
}

// CHHapticEventParameter
@(objc_class="CHHapticEventParameter")
	HapticEventParameter :: struct { using _: NS.Object }

@(objc_type=HapticEventParameter, objc_name="alloc", objc_is_class_method=true)
HapticEventParameter_alloc :: proc "c" () -> ^HapticEventParameter {
	return msgSend(^HapticEventParameter, HapticEventParameter, "alloc")
}

@(objc_type=HapticEventParameter, objc_name="initWithParameterID")
HapticEventParameter_initWithParameterID :: proc "c" (
	self: ^HapticEventParameter,
	parameter_id: EventParameterID,
	value: f32,
) -> ^HapticEventParameter {
	return msgSend(^HapticEventParameter, self, "initWithParameterID:value:", parameter_id, value)
}

// CHHapticPatternPlayer protocol - represented as opaque type
// This is a protocol in ObjC, but we can call methods on conforming objects
@(objc_class="NSObject")
	HapticPatternPlayer :: struct { using _: NS.Object }

@(objc_type=HapticPatternPlayer, objc_name="startAtTime")
HapticPatternPlayer_startAtTime :: proc "c" (self: ^HapticPatternPlayer, time: f64, error: ^^NS.Error) -> bool {
	return msgSend(NS.BOOL, self, "startAtTime:error:", time, error)
}

@(objc_type=HapticPatternPlayer, objc_name="stopAtTime")
HapticPatternPlayer_stopAtTime :: proc "c" (self: ^HapticPatternPlayer, time: f64, error: ^^NS.Error) -> bool {
	return msgSend(NS.BOOL, self, "stopAtTime:error:", time, error)
}

@(objc_type=HapticPatternPlayer, objc_name="cancelAndReturnError")
HapticPatternPlayer_cancelAndReturnError :: proc "c" (self: ^HapticPatternPlayer, error: ^^NS.Error) -> bool {
	return msgSend(NS.BOOL, self, "cancelAndReturnError:", error)
}
