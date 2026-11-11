class_name PlayerIntent
extends RefCounted
## What the player wants to do this frame, independent of the input device.
## Keyboard + mouse controls (later also gamepads, or the network) write it; the player
## controller reads it.

## Movement stick. x = right, y = forward. Length 0..1.
var move := Vector2.ZERO
var run := false
var jump_pressed := false  # one-shot, cleared when consumed
var jump_held := false
var guard_held := false
## Firing (only while in aim mode).
var fire_held := false
var fire_pressed := false  # one-shot, so a very quick tap still fires
## Toggle the manual aim mode (one-shot).
var aim_toggle := false
## Dashes requested since last read: directions in stick space (x = right, y = forward).
var dashes: Array[Vector2] = []
## True while the attack pad is held still long enough to charge a heavy attack.
var charge_held := false
## Attacks requested since last read (names from Movesets).
var attacks: Array[StringName] = []
## Camera drag accumulated since last read, in screen pixels.
var look_delta := Vector2.ZERO
## Lock-on toggle requested (Tab / middle mouse).
var lock_toggle := false


func clear_one_shots() -> void:
	jump_pressed = false
	lock_toggle = false
	fire_pressed = false
	aim_toggle = false
	look_delta = Vector2.ZERO
	attacks.clear()
	dashes.clear()
