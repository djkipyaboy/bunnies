extends SceneTree

# Headless test: Villager.is_vendor (2026-07-17 general store design §3.6) — a vendor emits
# vendor_interacted instead of dialogue_requested on interact; a normal Villager is unaffected.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_villager_vendor.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var ds: DialogueSet = DialogueSet.new()

	var normal: Villager = Villager.new()
	normal.dialogue = ds
	get_root().add_child(normal)
	var normal_dialogue_fired: Array[int] = [0]
	var normal_vendor_fired: Array[int] = [0]
	normal.dialogue_requested.connect(func(_d: DialogueSet) -> void: normal_dialogue_fired[0] += 1)
	normal.vendor_interacted.connect(func(_d: DialogueSet) -> void: normal_vendor_fired[0] += 1)
	normal._on_interacted()
	_check(normal_dialogue_fired[0] == 1, "a normal Villager (is_vendor false) emits dialogue_requested on interact")
	_check(normal_vendor_fired[0] == 0, "a normal Villager never emits vendor_interacted")

	var vendor: Villager = Villager.new()
	vendor.dialogue = ds
	vendor.is_vendor = true
	get_root().add_child(vendor)
	var vendor_dialogue_fired: Array[int] = [0]
	var vendor_vendor_fired: Array[int] = [0]
	vendor.dialogue_requested.connect(func(_d: DialogueSet) -> void: vendor_dialogue_fired[0] += 1)
	vendor.vendor_interacted.connect(func(_d: DialogueSet) -> void: vendor_vendor_fired[0] += 1)
	vendor._on_interacted()
	_check(vendor_vendor_fired[0] == 1, "a vendor Villager (is_vendor true) emits vendor_interacted on interact")
	_check(vendor_dialogue_fired[0] == 0, "a vendor Villager never ALSO emits dialogue_requested")

	normal.free()
	vendor.free()
	quit()
