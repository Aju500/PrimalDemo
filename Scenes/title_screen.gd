extends Control

@onready var loading_bar = $LoadingBar/LoadingBarFill
@onready var loading_bar_frame = $LoadingBar/LoadingBarFrame
@onready var start_button = $StartButton
@onready var fade_rect = $FadeRect

const LOAD_TIME := 5.0

var elapsed := 0.0

func _ready():
	start_button.visible = false
	start_button.pressed.connect(_on_start_pressed)

	loading_bar.min_value = 0
	loading_bar.max_value = 100
	loading_bar.value = 0

	fade_rect.color.a = 0.0

func _process(delta):
	if loading_bar.value >= 100:
		return

	elapsed += delta

	loading_bar.value = min((elapsed / LOAD_TIME) * 100.0, 100.0)

	if loading_bar.value >= 100:
		start_button.visible = true
		loading_bar.visible = false
		loading_bar_frame.visible = false

func _on_start_pressed():
	start_button.visible = false
	var tween = create_tween()

	tween.tween_property(
		fade_rect,
		"color:a",
		1.0,
		1.0
	)

	await tween.finished

	get_tree().change_scene_to_file("res://Scenes/save_select.tscn")
	fade_rect.visible = false
