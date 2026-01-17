#+build darwin

package karl2d_darwin_gamecontroller

// GameController framework bindings for macOS gamepad support
// Based on Apple's GCController API

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@private
msgSend :: intrinsics.objc_send

@require
foreign import GameController "system:GameController.framework"

@(link_prefix="GCController")
foreign GameController {
	DidConnectNotification: ^NS.String
	DidDisconnectNotification: ^NS.String
}

// GCHapticsLocality - to type the imported ^NSString constants
HapticsLocality :: ^NS.String

@(link_prefix="GCHapticsLocality")
foreign GameController {
	Default:      HapticsLocality
	All:          HapticsLocality
	Handles:      HapticsLocality
	LeftHandle:   HapticsLocality
	RightHandle:  HapticsLocality
	Triggers:     HapticsLocality
	LeftTrigger:  HapticsLocality
	RightTrigger: HapticsLocality
}

// GCHapticDurationInfinite - use for continuous haptics
HapticDurationInfinite: f64 : 1e300

// GCControllerPlayerIndex
ControllerPlayerIndexUnset :: NS.Integer(-1)

// Typed array for GCController results
@(objc_class="ControllerArray")
ControllerArray :: struct { using _: NS.Object }

@(objc_type=ControllerArray, objc_name="object")
ControllerArray_object :: proc "c" (self: ^ControllerArray, index: NS.UInteger) -> ^Controller {
	return msgSend(^Controller, self, "objectAtIndexedSubscript:", index)
}

@(objc_type=ControllerArray, objc_name="count")
ControllerArray_count :: proc "c" (self: ^ControllerArray) -> NS.UInteger {
	return msgSend(NS.UInteger, self, "count")
}

// GCController
@(objc_class="GCController")
Controller :: struct { using _: NS.Object }

@(objc_type=Controller, objc_name="controllers", objc_is_class_method=true)
Controller_controllers :: proc "c" () -> ^ControllerArray {
	return msgSend(^ControllerArray, Controller, "controllers")
}

@(objc_type=Controller, objc_name="startWirelessControllerDiscovery", objc_is_class_method=true)
Controller_startWirelessControllerDiscovery :: proc "c" (completion_handler: rawptr = nil) {
	msgSend(nil, Controller, "startWirelessControllerDiscoveryWithCompletionHandler:", completion_handler)
}

@(objc_type=Controller, objc_name="stopWirelessControllerDiscovery", objc_is_class_method=true)
Controller_stopWirelessControllerDiscovery :: proc "c" () {
	msgSend(nil, Controller, "stopWirelessControllerDiscovery")
}

@(objc_type=Controller, objc_name="extendedGamepad")
Controller_extendedGamepad :: proc "c" (self: ^Controller) -> ^ExtendedGamepad {
	return msgSend(^ExtendedGamepad, self, "extendedGamepad")
}

@(objc_type=Controller, objc_name="haptics")
Controller_haptics :: proc "c" (self: ^Controller) -> ^Haptics {
	return msgSend(^Haptics, self, "haptics")
}

@(objc_type=Controller, objc_name="playerIndex")
Controller_playerIndex :: proc "c" (self: ^Controller) -> NS.Integer {
	return msgSend(NS.Integer, self, "playerIndex")
}

@(objc_type=Controller, objc_name="setPlayerIndex")
Controller_setPlayerIndex :: proc "c" (self: ^Controller, index: NS.Integer) {
	msgSend(nil, self, "setPlayerIndex:", index)
}

@(objc_type=Controller, objc_name="vendorName")
Controller_vendorName :: proc "c" (self: ^Controller) -> ^NS.String {
	return msgSend(^NS.String, self, "vendorName")
}

// GCExtendedGamepad
@(objc_class="GCExtendedGamepad")
ExtendedGamepad :: struct { using _: NS.Object }

// Thumbsticks
@(objc_type=ExtendedGamepad, objc_name="leftThumbstick")
ExtendedGamepad_leftThumbstick :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerDirectionPad {
	return msgSend(^ControllerDirectionPad, self, "leftThumbstick")
}

@(objc_type=ExtendedGamepad, objc_name="rightThumbstick")
ExtendedGamepad_rightThumbstick :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerDirectionPad {
	return msgSend(^ControllerDirectionPad, self, "rightThumbstick")
}

// D-pad
@(objc_type=ExtendedGamepad, objc_name="dpad")
ExtendedGamepad_dpad :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerDirectionPad {
	return msgSend(^ControllerDirectionPad, self, "dpad")
}

// Face buttons
@(objc_type=ExtendedGamepad, objc_name="buttonA")
ExtendedGamepad_buttonA :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "buttonA")
}

@(objc_type=ExtendedGamepad, objc_name="buttonB")
ExtendedGamepad_buttonB :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "buttonB")
}

@(objc_type=ExtendedGamepad, objc_name="buttonX")
ExtendedGamepad_buttonX :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "buttonX")
}

@(objc_type=ExtendedGamepad, objc_name="buttonY")
ExtendedGamepad_buttonY :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "buttonY")
}

// Shoulder buttons
@(objc_type=ExtendedGamepad, objc_name="leftShoulder")
ExtendedGamepad_leftShoulder :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "leftShoulder")
}

@(objc_type=ExtendedGamepad, objc_name="rightShoulder")
ExtendedGamepad_rightShoulder :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "rightShoulder")
}

// Triggers
@(objc_type=ExtendedGamepad, objc_name="leftTrigger")
ExtendedGamepad_leftTrigger :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "leftTrigger")
}

@(objc_type=ExtendedGamepad, objc_name="rightTrigger")
ExtendedGamepad_rightTrigger :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "rightTrigger")
}

// Menu buttons
@(objc_type=ExtendedGamepad, objc_name="buttonMenu")
ExtendedGamepad_buttonMenu :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "buttonMenu")
}

@(objc_type=ExtendedGamepad, objc_name="buttonOptions")
ExtendedGamepad_buttonOptions :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "buttonOptions")
}

// Thumbstick buttons
@(objc_type=ExtendedGamepad, objc_name="leftThumbstickButton")
ExtendedGamepad_leftThumbstickButton :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "leftThumbstickButton")
}

@(objc_type=ExtendedGamepad, objc_name="rightThumbstickButton")
ExtendedGamepad_rightThumbstickButton :: proc "c" (self: ^ExtendedGamepad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "rightThumbstickButton")
}

// GCControllerDirectionPad
@(objc_class="GCControllerDirectionPad")
ControllerDirectionPad :: struct { using _: NS.Object }

@(objc_type=ControllerDirectionPad, objc_name="xAxis")
ControllerDirectionPad_xAxis :: proc "c" (self: ^ControllerDirectionPad) -> ^ControllerAxisInput {
	return msgSend(^ControllerAxisInput, self, "xAxis")
}

@(objc_type=ControllerDirectionPad, objc_name="yAxis")
ControllerDirectionPad_yAxis :: proc "c" (self: ^ControllerDirectionPad) -> ^ControllerAxisInput {
	return msgSend(^ControllerAxisInput, self, "yAxis")
}

@(objc_type=ControllerDirectionPad, objc_name="up")
ControllerDirectionPad_up :: proc "c" (self: ^ControllerDirectionPad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "up")
}

@(objc_type=ControllerDirectionPad, objc_name="down")
ControllerDirectionPad_down :: proc "c" (self: ^ControllerDirectionPad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "down")
}

@(objc_type=ControllerDirectionPad, objc_name="left")
ControllerDirectionPad_left :: proc "c" (self: ^ControllerDirectionPad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "left")
}

@(objc_type=ControllerDirectionPad, objc_name="right")
ControllerDirectionPad_right :: proc "c" (self: ^ControllerDirectionPad) -> ^ControllerButtonInput {
	return msgSend(^ControllerButtonInput, self, "right")
}

// GCControllerAxisInput
@(objc_class="GCControllerAxisInput")
ControllerAxisInput :: struct { using _: NS.Object }

@(objc_type=ControllerAxisInput, objc_name="value")
ControllerAxisInput_value :: proc "c" (self: ^ControllerAxisInput) -> f32 {
	return msgSend(f32, self, "value")
}

// GCControllerButtonInput
@(objc_class="GCControllerButtonInput")
ControllerButtonInput :: struct { using _: NS.Object }

@(objc_type=ControllerButtonInput, objc_name="isPressed")
ControllerButtonInput_isPressed :: proc "c" (self: ^ControllerButtonInput) -> bool {
	return msgSend(NS.BOOL, self, "isPressed")
}

@(objc_type=ControllerButtonInput, objc_name="value")
ControllerButtonInput_value :: proc "c" (self: ^ControllerButtonInput) -> f32 {
	return msgSend(f32, self, "value")
}

@(objc_type=ControllerButtonInput, objc_name="isTouched")
ControllerButtonInput_isTouched :: proc "c" (self: ^ControllerButtonInput) -> bool {
	return msgSend(NS.BOOL, self, "isTouched")
}

// GCHaptics - for creating haptic engines
@(objc_class="GCHaptics")
Haptics :: struct { using _: NS.Object }

@(objc_type=Haptics, objc_name="createEngineWithLocality")
Haptics_createEngineWithLocality :: proc "c" (self: ^Haptics, locality: HapticsLocality) -> ^HapticEngine {
	return msgSend(^HapticEngine, self, "createEngineWithLocality:", locality)
}
