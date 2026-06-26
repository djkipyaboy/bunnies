class_name TypeChartPanel
extends Panel

## Toggleable 6×6 type-effectiveness graphic (spec 2026-06-28). Rows = ATTACKER, columns = DEFENDER; each
## cell is the live multiplier (read from the DamageType .tres via multiplier_against, so it can never drift
## from combat math), filled by TypeVisuals.tier_color. Built once, hidden until toggled on; pure view.

const TYPE_PATHS: Array[String] = [
	"res://combat/resources/types/slashing.tres",
	"res://combat/resources/types/piercing.tres",
	"res://combat/resources/types/crushing.tres",
	"res://combat/resources/types/storm.tres",
	"res://combat/resources/types/mystic.tres",
	"res://combat/resources/types/earth.tres",
]

const PAD: float = 10.0
const TITLE_H: float = 20.0
const HEADER_H: float = 20.0
const ROW_H: float = 26.0
const ROWHDR_W: float = 46.0
const CELL_W: float = 48.0
const LEGEND_H: float = 18.0

var _types: Array[DamageType] = []
var _row_headers: Array[Panel] = []   # attacker row-header cells, for highlight_attacker

## Builds the whole widget. Call once after adding to the tree.
func build() -> void:
	_types.clear()
	for p: String in TYPE_PATHS:
		_types.append(load(p))

	var width: float = PAD * 2 + ROWHDR_W + CELL_W * 6.0
	var height: float = PAD * 2 + TITLE_H + LEGEND_H + HEADER_H + ROW_H * 6.0
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size

	var title := Label.new()
	title.text = "Type Chart — row attacks column"
	title.position = Vector2(PAD, PAD - 2.0)
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)

	var grid_top: float = PAD + TITLE_H + HEADER_H
	var grid_left: float = PAD + ROWHDR_W

	# Defender column headers (short names in identity color), with a small "DEF →" hint above-left.
	var def_hint := Label.new()
	def_hint.text = "atk↓ def→"
	def_hint.position = Vector2(PAD, PAD + TITLE_H)
	def_hint.add_theme_font_size_override("font_size", 10)
	def_hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	add_child(def_hint)
	for d: int in range(6):
		_add_header(_types[d].type, Vector2(grid_left + d * CELL_W, PAD + TITLE_H), CELL_W, HEADER_H)

	# Rows: attacker header + 6 cells.
	for a: int in range(6):
		var y: float = grid_top + a * ROW_H
		var rh: Panel = _add_header(_types[a].type, Vector2(PAD, y), ROWHDR_W, ROW_H)
		_row_headers.append(rh)
		for d: int in range(6):
			var mult: float = _types[a].multiplier_against(_types[d])
			_add_cell(mult, Vector2(grid_left + d * CELL_W, y))

	_add_legend(Vector2(PAD, height - PAD - LEGEND_H + 2.0))

## A header cell (short type name on its identity color). Returns it so the row variant can be highlighted.
func _add_header(type_enum: int, pos: Vector2, w: float, h: float) -> Panel:
	var cell := Panel.new()
	cell.position = pos
	cell.size = Vector2(w - 2.0, h - 2.0)
	var box := StyleBoxFlat.new()
	box.bg_color = TypeVisuals.type_color(type_enum).darkened(0.45)
	box.set_corner_radius_all(3)
	cell.add_theme_stylebox_override("panel", box)
	var lbl := Label.new()
	lbl.text = TypeVisuals.short_name(type_enum)
	lbl.size = cell.size
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", TypeVisuals.type_color(type_enum))
	cell.add_child(lbl)
	add_child(cell)
	return cell

## A data cell: the multiplier on its tier color.
func _add_cell(mult: float, pos: Vector2) -> void:
	var cell := Panel.new()
	cell.position = pos
	cell.size = Vector2(CELL_W - 2.0, ROW_H - 2.0)
	var box := StyleBoxFlat.new()
	box.bg_color = TypeVisuals.tier_color(mult)
	box.set_corner_radius_all(3)
	cell.add_theme_stylebox_override("panel", box)
	var lbl := Label.new()
	lbl.text = "×%s" % mult
	lbl.size = cell.size
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98) if mult != 1.0 else Color(0.7, 0.72, 0.78))
	cell.add_child(lbl)
	add_child(cell)

## A one-line legend: green strong / gray neutral / orange weak / red resisted.
func _add_legend(pos: Vector2) -> void:
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.position = pos
	legend.size = Vector2(size.x - PAD * 2, LEGEND_H)
	legend.add_theme_font_size_override("normal_font_size", 11)
	var g: String = TypeVisuals.tier_color(1.25).lightened(0.25).to_html(false)
	var o: String = TypeVisuals.tier_color(0.75).lightened(0.25).to_html(false)
	var r: String = TypeVisuals.tier_color(0.5).lightened(0.25).to_html(false)
	legend.text = "[color=#%s]■[/color] ≥×1.25 strong   [color=#90929a]■[/color] ×1.0   [color=#%s]■[/color] ×0.75 weak   [color=#%s]■[/color] ≤×0.5 resisted" % [g, o, r]
	add_child(legend)

## Faintly outlines the given attacker's row-header so the toggling PC finds its matchups fast. Pass -1 to
## clear. Re-applied each time the chart is shown (the active class can change between fights).
func highlight_attacker(type_enum: int) -> void:
	for i: int in range(_row_headers.size()):
		var rh: Panel = _row_headers[i]
		var box: StyleBoxFlat = rh.get_theme_stylebox("panel")
		if i == type_enum:
			box.set_border_width_all(2)
			box.border_color = Color(1, 1, 1)
		else:
			box.set_border_width_all(0)
