extends Node

const MOD_ID := "ImmersiveInventory"
const MOD_FRIENDLY_NAME := "ImmersiveInventory"
const MOD_DESCRIPTION := "Configures the equipment-driven inventory layout and its 2-row compact mode."
const FILE_PATH := "user://MCM/ImmersiveInventory"
const CONFIG_FILE_NAME := "config.ini"
const MCM_HELPERS_PATH := "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"

const BASE_ROWS := 2
const BASE_WIDTH := 8
const MIN_EXTRA_ROWS := 0
const MAX_EXTRA_ROWS := 12
const MIN_BONUS_ROWS := 0
const MAX_BONUS_ROWS := 4
const DEFAULT_TOTAL_ROWS := 2
const MIN_SECTION_ROWS := 1
const MAX_SECTION_ROWS := 14
const MIN_SECTION_COLS := 1
const MAX_SECTION_COLS := 8

var enabled: bool = true
var compact_mode: bool = true
var extra_rows: int = 0
var slot_bonus_rows: Dictionary = {
	"Backpack": 3,
	"Rig": 2,
	"Torso": 1,
	"Legs": 1,
	"Belt": 1,
}
var backpack_default_rows: int = 5
var backpack_jaakari_rows: int = 7
var backpack_capacity_per_row: float = 5.0
var backpack_capacity_scaling_enabled: bool = true
var backpack_min_rows: int = 3
var backpack_max_rows: int = 12
var rig_default_rows: int = 2
var rig_fisher_rows: int = 1
var jaakari_weapon_slot_enabled: bool = true
var jaakari_weapon_slot_columns: int = 2
var jaakari_weapon_slot_rows: int = 1
var _is_reloading: bool = false

func _ready() -> void:
	_ensure_config_exists()
	_register_with_mcm()

func ReloadFromDisk() -> void:
	if _is_reloading:
		return

	var configPath: String = FILE_PATH.path_join(CONFIG_FILE_NAME)
	if !FileAccess.file_exists(configPath):
		return

	var diskConfig: ConfigFile = ConfigFile.new()
	if diskConfig.load(configPath) != OK:
		return

	_is_reloading = true
	_apply_runtime_values(diskConfig)
	_is_reloading = false

func get_total_rows() -> int:
	if !enabled || !compact_mode:
		return clamp(12 + extra_rows, BASE_ROWS, 12 + MAX_EXTRA_ROWS)

	return clamp(BASE_ROWS + extra_rows + get_slot_bonus_total(), BASE_ROWS, BASE_ROWS + MAX_EXTRA_ROWS + MAX_BONUS_ROWS * slot_bonus_rows.size())

func get_bonus_rows_for_slot(slotName: String) -> int:
	if !slot_bonus_rows.has(slotName):
		return 0

	return clamp(int(slot_bonus_rows[slotName]), MIN_BONUS_ROWS, MAX_BONUS_ROWS)

func get_slot_bonus_total() -> int:
	var totalBonus: int = 0
	for slotName in slot_bonus_rows.keys():
		totalBonus += get_bonus_rows_for_slot(str(slotName))

	return totalBonus

func get_backpack_rows_for_item(itemData) -> int:
	if itemData == null:
		return clamp(backpack_default_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

	var filePath: String = str(itemData.file)
	if filePath.find("Backpack_Jaeger") != -1:
		return clamp(backpack_jaakari_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

	if !backpack_capacity_scaling_enabled:
		return clamp(backpack_default_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

	var capacity: float = float(itemData.capacity)
	var rowsFromCapacity: int = int(ceil(capacity / max(1.0, backpack_capacity_per_row)))
	rowsFromCapacity = clamp(rowsFromCapacity, backpack_min_rows, backpack_max_rows)
	return clamp(rowsFromCapacity, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

func get_rig_rows_for_item(itemData) -> int:
	if itemData == null:
		return clamp(rig_default_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

	var filePath: String = str(itemData.file)
	if filePath.find("Vest_Fishing") != -1:
		return clamp(rig_fisher_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

	return clamp(rig_default_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)

func get_jaakari_weapon_slot_size() -> Vector2:
	return Vector2(
		clamp(jaakari_weapon_slot_columns, MIN_SECTION_COLS, MAX_SECTION_COLS),
		clamp(jaakari_weapon_slot_rows, MIN_SECTION_ROWS, MAX_SECTION_ROWS)
	)

func _ensure_config_exists() -> void:
	DirAccess.make_dir_recursive_absolute(FILE_PATH)

	var config: ConfigFile = ConfigFile.new()
	_populate_config_defaults(config)

	var configPath: String = FILE_PATH.path_join(CONFIG_FILE_NAME)
	if !FileAccess.file_exists(configPath):
		config.save(configPath)
		return

	if config.load(configPath) != OK:
		config = ConfigFile.new()
		_populate_config_defaults(config)

	config.save(configPath)
	UpdateConfigProperties(config)

func _register_with_mcm() -> void:
	var mcmHelpers = load(MCM_HELPERS_PATH)
	if !mcmHelpers:
		return

	if !mcmHelpers.has_method("RegisterConfiguration"):
		return

	mcmHelpers.RegisterConfiguration(
		MOD_ID,
		MOD_FRIENDLY_NAME,
		FILE_PATH,
		MOD_DESCRIPTION,
		{
			CONFIG_FILE_NAME: Callable(self, "UpdateConfigProperties")
		}
	)

func UpdateConfigProperties(config: ConfigFile) -> void:
	_apply_runtime_values(config)
	var ui = get_tree().root.get_node_or_null("Map/Core/UI/Interface")
	if ui && ui.has_method("RefreshImmersiveInventory"):
		ui.RefreshImmersiveInventory()

func _apply_runtime_values(config: ConfigFile) -> void:
	enabled = bool(_read_value(config, "Bool", "enabled", enabled))
	compact_mode = bool(_read_value(config, "Bool", "compact_mode", compact_mode))
	extra_rows = clamp(int(_read_value(config, "Int", "extra_rows", extra_rows)), MIN_EXTRA_ROWS, MAX_EXTRA_ROWS)

	for slotName in slot_bonus_rows.keys():
		var currentValue: int = int(slot_bonus_rows[slotName])
		var newValue: int = int(_read_value(config, "Int", "rows_" + str(slotName), currentValue))
		slot_bonus_rows[slotName] = clamp(newValue, MIN_BONUS_ROWS, MAX_BONUS_ROWS)

	backpack_default_rows = clamp(int(_read_value(config, "Int", "backpack_default_rows", backpack_default_rows)), MIN_SECTION_ROWS, MAX_SECTION_ROWS)
	backpack_jaakari_rows = clamp(int(_read_value(config, "Int", "backpack_jaakari_rows", backpack_jaakari_rows)), MIN_SECTION_ROWS, MAX_SECTION_ROWS)
	backpack_capacity_per_row = clamp(float(_read_value(config, "Float", "backpack_capacity_per_row", backpack_capacity_per_row)), 1.0, 12.0)
	backpack_capacity_scaling_enabled = bool(_read_value(config, "Bool", "backpack_capacity_scaling_enabled", backpack_capacity_scaling_enabled))
	backpack_min_rows = clamp(int(_read_value(config, "Int", "backpack_min_rows", backpack_min_rows)), MIN_SECTION_ROWS, MAX_SECTION_ROWS)
	backpack_max_rows = clamp(int(_read_value(config, "Int", "backpack_max_rows", backpack_max_rows)), backpack_min_rows, MAX_SECTION_ROWS)
	rig_default_rows = clamp(int(_read_value(config, "Int", "rig_default_rows", rig_default_rows)), MIN_SECTION_ROWS, MAX_SECTION_ROWS)
	rig_fisher_rows = clamp(int(_read_value(config, "Int", "rig_fisher_rows", rig_fisher_rows)), MIN_SECTION_ROWS, MAX_SECTION_ROWS)
	jaakari_weapon_slot_enabled = bool(_read_value(config, "Bool", "jaakari_weapon_slot_enabled", jaakari_weapon_slot_enabled))
	jaakari_weapon_slot_columns = clamp(int(_read_value(config, "Int", "jaakari_weapon_slot_columns", jaakari_weapon_slot_columns)), MIN_SECTION_COLS, MAX_SECTION_COLS)
	jaakari_weapon_slot_rows = clamp(int(_read_value(config, "Int", "jaakari_weapon_slot_rows", jaakari_weapon_slot_rows)), MIN_SECTION_ROWS, MAX_SECTION_ROWS)

	var totalRows: int = get_total_rows()
	print("[ImmersiveInventoryMod] Config apply enabled=%s compact_mode=%s extra_rows=%d total_rows=%d" % [str(enabled), str(compact_mode), extra_rows, totalRows])

func _populate_config_defaults(config: ConfigFile) -> void:
	config.set_value("Bool", "enabled", {
		"name": "Enabled",
		"tooltip": "Master toggle for the equipment-driven inventory layout mod.",
		"default": true,
		"value": true,
	})

	config.set_value("Bool", "compact_mode", {
		"name": "Compact Mode",
		"tooltip": "Use the 2-row base inventory and expand it from equipped gear.",
		"default": true,
		"value": true,
	})

	config.set_value("Int", "extra_rows", {
		"name": "Extra Rows",
		"tooltip": "Additional rows added on top of the compact base layout.",
		"default": 0,
		"value": 0,
		"minRange": MIN_EXTRA_ROWS,
		"maxRange": MAX_EXTRA_ROWS,
	})

	for slotName in slot_bonus_rows.keys():
		var defaultValue: int = int(slot_bonus_rows[slotName])
		config.set_value("Int", "rows_" + str(slotName), {
			"name": "%s Bonus Rows" % str(slotName),
			"tooltip": "Rows unlocked by the equipped %s slot." % str(slotName),
			"default": defaultValue,
			"value": defaultValue,
			"minRange": MIN_BONUS_ROWS,
			"maxRange": MAX_BONUS_ROWS,
		})

	config.set_value("Bool", "backpack_capacity_scaling_enabled", {
		"name": "Backpack Capacity Scaling",
		"tooltip": "Scale backpack section rows by equipped backpack capacity.",
		"default": true,
		"value": true,
	})

	config.set_value("Float", "backpack_capacity_per_row", {
		"name": "Backpack Capacity Per Row",
		"tooltip": "How much backpack capacity translates to one inventory row (lower = more rows).",
		"default": 5.0,
		"value": 5.0,
		"minRange": 1.0,
		"maxRange": 12.0,
	})

	config.set_value("Int", "backpack_default_rows", {
		"name": "Backpack Default Rows",
		"tooltip": "Fallback rows for backpacks when no special rule applies.",
		"default": 5,
		"value": 5,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

	config.set_value("Int", "backpack_jaakari_rows", {
		"name": "Backpack Jääkäri Rows",
		"tooltip": "Rows for Jääkäri backpacks (the largest backpack profile).",
		"default": 7,
		"value": 7,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

	config.set_value("Int", "backpack_min_rows", {
		"name": "Backpack Min Rows",
		"tooltip": "Minimum backpack rows when capacity scaling is enabled.",
		"default": 3,
		"value": 3,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

	config.set_value("Int", "backpack_max_rows", {
		"name": "Backpack Max Rows",
		"tooltip": "Maximum backpack rows when capacity scaling is enabled.",
		"default": 12,
		"value": 12,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

	config.set_value("Int", "rig_default_rows", {
		"name": "Rig Default Rows",
		"tooltip": "Rows for regular chest rigs.",
		"default": 2,
		"value": 2,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

	config.set_value("Int", "rig_fisher_rows", {
		"name": "Fisher Vest Rows",
		"tooltip": "Rows for the Fisher vest (should be smaller than regular vests).",
		"default": 1,
		"value": 1,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

	config.set_value("Bool", "jaakari_weapon_slot_enabled", {
		"name": "Jääkäri Bonus Weapon Slot",
		"tooltip": "Enable the extra Jääkäri-only weapon section in the inventory panel.",
		"default": true,
		"value": true,
	})

	config.set_value("Int", "jaakari_weapon_slot_columns", {
		"name": "Jääkäri Weapon Slot Columns",
		"tooltip": "Columns for the Jääkäri bonus weapon slot.",
		"default": 2,
		"value": 2,
		"minRange": MIN_SECTION_COLS,
		"maxRange": MAX_SECTION_COLS,
	})

	config.set_value("Int", "jaakari_weapon_slot_rows", {
		"name": "Jääkäri Weapon Slot Rows",
		"tooltip": "Rows for the Jääkäri bonus weapon slot.",
		"default": 1,
		"value": 1,
		"minRange": MIN_SECTION_ROWS,
		"maxRange": MAX_SECTION_ROWS,
	})

func _read_value(config: ConfigFile, section: String, key: String, fallback):
	if !config.has_section_key(section, key):
		return fallback

	var entry = config.get_value(section, key, fallback)
	if entry is Dictionary and entry.has("value"):
		return entry["value"]

	return entry
