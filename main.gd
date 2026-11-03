extends Control

const GRID_SIZE := 8
const TILE_WIDTH := 72.0
const TILE_HEIGHT := 38.0
const SAVE_PATH := "user://morepower_save.json"
const OFFLINE_CAP_SECONDS := 28800.0

const GENERATORS := {
	"Wind": {"cost": 45.0, "output": 2.0, "color": Color("#75d7c3"), "unlock": 0.0},
	"Solar": {"cost": 110.0, "output": 5.0, "color": Color("#f6cc69"), "unlock": 100.0},
	"Hydro": {"cost": 320.0, "output": 16.0, "color": Color("#62a9ed"), "unlock": 400.0},
	"Nuclear": {"cost": 1200.0, "output": 80.0, "color": Color("#d58bea"), "unlock": 1400.0}
}

var buildings: Dictionary = {}
var selected_generator := "Wind"
var credits := 160.0
var lifetime_credits := 0.0
var energy_kwh := 0.0
var multiplier := 1.0
var upgrade_cost := 250.0
var generation_kw := 0.0
var save_clock := 0.0
var hud_clock := 0.0
var offline_notice := ""

var credits_label: Label
var output_label: Label
var energy_label: Label
var upgrade_button: Button
var generator_buttons: Dictionary = {}
var message_label: Label


func _ready() -> void:
	_load_game()
	_build_hud()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var produced_kw := _calculate_output()
	generation_kw = produced_kw
	energy_kwh += produced_kw * delta / 3600.0
	var earned := produced_kw * delta * 0.12
	credits += earned
	lifetime_credits += earned

	save_clock += delta
	hud_clock += delta
	if save_clock >= 10.0:
		_save_game()
		save_clock = 0.0
	if hud_clock >= 0.25:
		_update_hud()
		queue_redraw()
		hud_clock = 0.0


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var left_panel := PanelContainer.new()
	left_panel.position = Vector2(18, 18)
	left_panel.custom_minimum_size = Vector2(284, 0)
	overlay.add_child(left_panel)
	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_column)

	var title := Label.new()
	title.text = "MOREPOWER"
	title.add_theme_font_size_override("font_size", 25)
	left_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Build a brighter grid, one tile at a time."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_column.add_child(subtitle)

	credits_label = Label.new()
	output_label = Label.new()
	energy_label = Label.new()
	for stat in [credits_label, output_label, energy_label]:
		stat.add_theme_font_size_override("font_size", 18)
		left_column.add_child(stat)

	var divider := HSeparator.new()
	left_column.add_child(divider)
	var build_title := Label.new()
	build_title.text = "BUILD GENERATORS"
	build_title.add_theme_font_size_override("font_size", 15)
	left_column.add_child(build_title)

	for generator_name in GENERATORS:
		var button := Button.new()
		generator_buttons[generator_name] = button
		button.custom_minimum_size = Vector2(0, 42)
		button.pressed.connect(_select_generator.bind(generator_name))
		left_column.add_child(button)

	upgrade_button = Button.new()
	upgrade_button.custom_minimum_size = Vector2(0, 44)
	upgrade_button.pressed.connect(_buy_upgrade)
	left_column.add_child(upgrade_button)

	message_label = Label.new()
	message_label.text = "Choose a generator, then click an empty tile."
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_column.add_child(message_label)

	var help := Label.new()
	help.text = "Production earns credits and electricity over time. Your grid is saved automatically."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_column.add_child(help)

	var right_panel := PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.offset_left = -282
	right_panel.offset_right = -18
	right_panel.offset_top = 18
	right_panel.offset_bottom = 66
	overlay.add_child(right_panel)
	var right_label := Label.new()
	right_label.text = "POWER PARK  •  CLICK AN EMPTY DIAMOND TO BUILD"
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_panel.add_child(right_label)

	_update_hud()


func _update_hud() -> void:
	if not is_instance_valid(credits_label):
		return
	credits_label.text = "Credits  $%s" % _format_number(credits)
	output_label.text = "Grid output  %.1f kW" % generation_kw
	energy_label.text = "Electricity  %s kWh" % _format_number(energy_kwh)

	for generator_name in GENERATORS:
		var data: Dictionary = GENERATORS[generator_name]
		var button: Button = generator_buttons[generator_name]
		var is_unlocked: bool = lifetime_credits >= float(data["unlock"])
		var cost := float(data["cost"])
		button.disabled = not is_unlocked or credits < cost
		if not is_unlocked:
			button.text = (
				"%s  •  Unlock at $%s" % [generator_name, _format_number(float(data["unlock"]))]
			)
		else:
			button.text = (
				"%s  •  %.0f kW  •  $%s%s"
				% [
					generator_name,
					float(data["output"]) * multiplier,
					_format_number(cost),
					"  ✓" if selected_generator == generator_name else ""
				]
			)

	upgrade_button.text = "Grid upgrade  x2  •  $%s" % _format_number(upgrade_cost)
	upgrade_button.disabled = credits < upgrade_cost
	if not offline_notice.is_empty():
		message_label.text = offline_notice


func _select_generator(generator_name: String) -> void:
	selected_generator = generator_name
	message_label.text = "%s selected. Click an empty tile to place it." % generator_name
	_update_hud()


func _buy_upgrade() -> void:
	if credits < upgrade_cost:
		return
	credits -= upgrade_cost
	multiplier *= 2.0
	upgrade_cost *= 2.5
	message_label.text = "Grid upgraded! Every generator now produces twice as much."
	_update_hud()
	_save_game()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _screen_to_cell(event.position)
		if cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE:
			_place_generator(cell)


func _place_generator(cell: Vector2i) -> void:
	var key := _cell_key(cell)
	if buildings.has(key):
		message_label.text = "That tile is occupied. Choose another diamond."
		return
	var data: Dictionary = GENERATORS[selected_generator]
	var cost := float(data["cost"])
	if lifetime_credits < float(data["unlock"]):
		message_label.text = "Earn more lifetime credits to unlock %s." % selected_generator
		return
	if credits < cost:
		message_label.text = "Not enough credits for %s." % selected_generator
		return

	credits -= cost
	buildings[key] = selected_generator
	message_label.text = "%s connected to the grid!" % selected_generator
	_update_hud()
	_save_game()
	queue_redraw()


func _calculate_output() -> float:
	var output := 0.0
	for generator_name in buildings.values():
		var data: Dictionary = GENERATORS.get(generator_name, GENERATORS["Wind"])
		output += float(data["output"]) * multiplier
	return output


func _draw() -> void:
	var origin := _map_origin()
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell := Vector2i(x, y)
			var center := _cell_center(cell)
			var points := PackedVector2Array(
				[
					center + Vector2(0, -TILE_HEIGHT / 2.0),
					center + Vector2(TILE_WIDTH / 2.0, 0),
					center + Vector2(0, TILE_HEIGHT / 2.0),
					center + Vector2(-TILE_WIDTH / 2.0, 0)
				]
			)
			var shade := 0.0 if (x + y) % 2 == 0 else 0.035
			draw_colored_polygon(points, Color(0.14 + shade, 0.27 + shade, 0.25 + shade, 1.0))
			for i in range(4):
				draw_line(points[i], points[(i + 1) % 4], Color("#365c54"), 1.5, true)
			var key := _cell_key(cell)
			if buildings.has(key):
				_draw_generator(center, str(buildings[key]))
	_draw_circle(origin + Vector2(0, 0), 2.0, Color("#ffffff"))


func _draw_generator(center: Vector2, generator_name: String) -> void:
	var data: Dictionary = GENERATORS.get(generator_name, GENERATORS["Wind"])
	var color: Color = data["color"]
	match generator_name:
		"Wind":
			draw_colored_polygon(
				PackedVector2Array(
					[
						center + Vector2(-12, -3),
						center + Vector2(12, -3),
						center + Vector2(12, 4),
						center + Vector2(-12, 4)
					]
				),
				Color("#42535b")
			)
			draw_line(center + Vector2(0, -3), center + Vector2(0, -28), color, 3.0, true)
			draw_line(center + Vector2(0, -28), center + Vector2(-11, -40), color, 3.0, true)
			draw_line(center + Vector2(0, -28), center + Vector2(13, -31), color, 3.0, true)
			draw_line(center + Vector2(0, -28), center + Vector2(2, -13), color, 3.0, true)
			draw_circle(center + Vector2(0, -28), 4.0, Color("#eef7f2"))
		"Solar":
			var panel := Rect2(center + Vector2(-16, -15), Vector2(32, 19))
			draw_rect(panel, Color("#345579"))
			draw_rect(panel, color, false, 2.0)
			draw_line(panel.position + Vector2(0, 9), panel.position + Vector2(32, 9), color, 1.0)
			draw_line(panel.position + Vector2(11, 0), panel.position + Vector2(11, 19), color, 1.0)
			draw_line(panel.position + Vector2(22, 0), panel.position + Vector2(22, 19), color, 1.0)
			draw_line(center + Vector2(-9, 5), center + Vector2(-12, 13), Color("#c1d2c8"), 2.0)
			draw_line(center + Vector2(9, 5), center + Vector2(12, 13), Color("#c1d2c8"), 2.0)
		"Hydro":
			draw_colored_polygon(
				PackedVector2Array(
					[
						center + Vector2(-17, 0),
						center + Vector2(0, -17),
						center + Vector2(17, 0),
						center + Vector2(0, 10)
					]
				),
				Color("#3d5965")
			)
			draw_line(center + Vector2(-12, 0), center + Vector2(12, 0), color, 4.0)
			draw_line(center + Vector2(-9, 7), center + Vector2(9, 7), color, 3.0)
		"Nuclear":
			draw_colored_polygon(
				PackedVector2Array(
					[
						center + Vector2(-16, 8),
						center + Vector2(-12, -17),
						center + Vector2(-5, -17),
						center + Vector2(-2, 8)
					]
				),
				Color("#8a607d")
			)
			draw_colored_polygon(
				PackedVector2Array(
					[
						center + Vector2(3, 8),
						center + Vector2(7, -17),
						center + Vector2(14, -17),
						center + Vector2(17, 8)
					]
				),
				Color("#8a607d")
			)
			draw_colored_polygon(
				PackedVector2Array(
					[
						center + Vector2(-19, 8),
						center + Vector2(20, 8),
						center + Vector2(15, 15),
						center + Vector2(-14, 15)
					]
				),
				color
			)


func _map_origin() -> Vector2:
	return Vector2(size.x * 0.62, 265.0)


func _cell_center(cell: Vector2i) -> Vector2:
	return (
		_map_origin()
		+ Vector2(
			float(cell.x - cell.y) * TILE_WIDTH / 2.0, float(cell.x + cell.y) * TILE_HEIGHT / 2.0
		)
	)


func _screen_to_cell(position: Vector2) -> Vector2i:
	var relative := position - _map_origin()
	var grid_x := relative.x / TILE_WIDTH + relative.y / TILE_HEIGHT
	var grid_y := relative.y / TILE_HEIGHT - relative.x / TILE_WIDTH
	return Vector2i(floori(grid_x + 0.5), floori(grid_y + 0.5))


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _format_number(value: float) -> String:
	if value >= 1000000.0:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.2fK" % (value / 1000.0)
	return "%.1f" % value


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open the save file for reading.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Save file is invalid; starting a new grid.")
		return

	var data: Dictionary = parsed
	credits = maxf(0.0, float(data.get("credits", credits)))
	lifetime_credits = maxf(0.0, float(data.get("lifetime_credits", lifetime_credits)))
	energy_kwh = maxf(0.0, float(data.get("energy_kwh", energy_kwh)))
	multiplier = maxf(1.0, float(data.get("multiplier", multiplier)))
	upgrade_cost = maxf(250.0, float(data.get("upgrade_cost", upgrade_cost)))
	var loaded_buildings: Variant = data.get("buildings", {})
	if loaded_buildings is Dictionary:
		for key in loaded_buildings:
			var generator_name := str(loaded_buildings[key])
			if GENERATORS.has(generator_name):
				buildings[str(key)] = generator_name
	var elapsed := clampf(
		(
			Time.get_unix_time_from_system()
			- float(data.get("saved_at", Time.get_unix_time_from_system()))
		),
		0.0,
		OFFLINE_CAP_SECONDS
	)
	var offline_output := _calculate_output()
	if elapsed >= 60.0 and offline_output > 0.0:
		var offline_energy := offline_output * elapsed / 3600.0
		var offline_credits := offline_output * elapsed * 0.12
		energy_kwh += offline_energy
		credits += offline_credits
		lifetime_credits += offline_credits
		offline_notice = (
			"Welcome back! Your grid made %s kWh and $%s while away."
			% [_format_number(offline_energy), _format_number(offline_credits)]
		)


func _save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open the save file for writing.")
		return
	var save_data := {
		"credits": credits,
		"lifetime_credits": lifetime_credits,
		"energy_kwh": energy_kwh,
		"multiplier": multiplier,
		"upgrade_cost": upgrade_cost,
		"buildings": buildings,
		"saved_at": Time.get_unix_time_from_system()
	}
	file.store_string(JSON.stringify(save_data))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
