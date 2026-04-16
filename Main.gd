extends "res://mods/ImmersiveInventory/BaseMain.gd"

func _ready() -> void:
	super()
	print("[ImmersiveInventoryMod] _ready start")
	_override_script("res://mods/ImmersiveInventory/Interface_Mod.gd")
	_override_script("res://mods/ImmersiveInventory/Grid_Mod.gd")
	print("[ImmersiveInventoryMod] Overrides loaded")

func _override_script(mod_script_path: String) -> void:
	var script: Script = load(mod_script_path)
	if !script:
		push_error("[ImmersiveInventoryMod] Failed to load: " + mod_script_path)
		return

	script.reload()

	var parent_script: Script = script.get_base_script()
	if !parent_script:
		push_error("[ImmersiveInventoryMod] No base script for: " + mod_script_path)
		return

	var target_path: String = str(parent_script.resource_path)
	if target_path == "" || target_path == "res://" || !target_path.ends_with(".gd"):
		push_error("[ImmersiveInventoryMod] Invalid base script path for %s: %s" % [mod_script_path, target_path])
		return

	print("[ImmersiveInventoryMod] Taking over path: " + target_path)
	script.take_over_path(target_path)
