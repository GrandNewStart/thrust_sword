class_name ScreenFx
extends ColorRect
## Full-screen post effects (see shaders/screen_fx.gdshader). Kicked by FxDirector, decays on
## its own; hidden entirely when idle so it costs nothing.

## Blur strengths (smear as a fraction of the distance to the screen centre).
@export var run_blur := 0.03
@export var dash_blur := 0.24
## How fast a dash's blur fades once the dash is over (strength per second).
@export var blur_decay := 0.75
## How quickly the held (running / dashing) blur follows its target: snaps in, eases out.
@export var hold_rise_sharpness := 35.0
@export var hold_fall_sharpness := 10.0
@export var aberration_decay := 3.0
@export var vignette_decay := 2.5

## One-off blur that fades on its own (e.g. after a dash).
var blur := 0.0
## Blur held while a condition lasts (running, dashing); set every frame via hold_blur().
var held_blur := 0.0
var _held_target := 0.0
## Edge darkening held while requested each frame (charging focus).
var darken := 0.0
var _darken_target := 0.0
var aberration := 0.0
var vignette := 0.0
var _mat := ShaderMaterial.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = load("res://shaders/screen_fx.gdshader")
	material = _mat
	visible = false


func kick_blur(amount: float) -> void:
	blur = maxf(blur, amount)


func hold_darken(amount: float) -> void:
	_darken_target = amount


## Keep at least this much blur for now (call every frame; 0 = none).
func hold_blur(amount: float) -> void:
	_held_target = amount


func kick_aberration(amount: float) -> void:
	aberration = maxf(aberration, amount)


func kick_vignette(amount: float) -> void:
	vignette = maxf(vignette, amount)


func _process(delta: float) -> void:
	blur = maxf(0.0, blur - delta * blur_decay)
	var sharp := hold_rise_sharpness if _held_target > held_blur else hold_fall_sharpness
	held_blur = lerpf(held_blur, _held_target, 1.0 - exp(-sharp * delta))
	if held_blur < 0.0005:
		held_blur = 0.0
	var total_blur := maxf(blur, held_blur)
	darken = lerpf(darken, _darken_target, 1.0 - exp(-8.0 * delta))
	if darken < 0.002:
		darken = 0.0
	aberration = maxf(0.0, aberration - delta * aberration_decay)
	vignette = maxf(0.0, vignette - delta * vignette_decay)
	visible = total_blur > 0.0005 or aberration > 0.001 or vignette > 0.001 or darken > 0.0
	if visible:
		_mat.set_shader_parameter("blur", total_blur)
		_mat.set_shader_parameter("darken", darken)
		_mat.set_shader_parameter("aberration", aberration)
		_mat.set_shader_parameter("vignette", vignette)
