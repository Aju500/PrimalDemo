extends Control
# The enemy, as a coloured shape (placeholder for art). Click it to Observe.
# Hovering swaps the cursor to an eye: a white circle with a smaller black one inside.

signal clicked

var col   : Color  = Color(0.8, 0.8, 0.8)
var shape : String = "circle"

static var _eye_tex : ImageTexture = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


func setup(c: Color, s: String) -> void:
	col = c
	shape = s
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


func _draw() -> void:
	var c := size * 0.5
	var rad := minf(size.x, size.y) * 0.42
	match shape:
		"square":
			draw_rect(Rect2(c - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0)), col)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -rad), c + Vector2(rad, rad * 0.85), c + Vector2(-rad, rad * 0.85)
			]), col)
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -rad), c + Vector2(rad * 0.8, 0), c + Vector2(0, rad), c + Vector2(-rad * 0.8, 0)
			]), col)
		"hex":
			var pts := PackedVector2Array()
			for i in 6:
				var a := deg_to_rad(60.0 * float(i) - 90.0)
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			draw_colored_polygon(pts, col)
		_:
			draw_circle(c, rad, col)


func _on_enter() -> void:
	Input.set_custom_mouse_cursor(_eye_texture(), Input.CURSOR_ARROW, Vector2(16, 16))


func _on_exit() -> void:
	Input.set_custom_mouse_cursor(null)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)


static func _eye_texture() -> ImageTexture:
	if _eye_tex != null:
		return _eye_tex
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			if d <= 14.0:
				img.set_pixel(x, y, Color.WHITE)
			if d <= 5.5:
				img.set_pixel(x, y, Color.BLACK)
	_eye_tex = ImageTexture.create_from_image(img)
	return _eye_tex
