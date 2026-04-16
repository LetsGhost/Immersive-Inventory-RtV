extends "res://Scripts/Interface.gd"

const BASE_ROWS := 2
const BASE_WIDTH := 8
const MAX_ALLOWED_ROWS := 34
const CONFIG_NODE_PATH := "/root/ImmersiveInventoryConfig"

const MOD_CELL_SIZE := 64.0
const MOD_HEADER_HEIGHT := 32.0
const MOD_VIEW_WIDTH := 512.0
const MOD_VIEW_HEIGHT := 768.0
const MOD_SCROLLBAR_NAME := "EquipmentInventoryScrollBar"
const MOD_SCROLLBAR_WIDTH := 14.0
const MOD_SCROLLBAR_GAP := 4.0
const MOD_TOTAL_WIDTH := MOD_VIEW_WIDTH + MOD_SCROLLBAR_GAP + MOD_SCROLLBAR_WIDTH
const GAME_UI_THEME := preload("res://UI/Themes/Theme.tres")
const GRID_TEXTURE := preload("res://UI/Sprites/Tile.png")
const POCKETS_GRID_SIZE := Vector2(5, 1)
const PANTS_GRID_SIZE := Vector2(2, 1)
const JACKET_GRID_SIZE := Vector2(6, 1)
const CHEST_RIG_GRID_SIZE := Vector2(8, 2)
const BELT_GRID_SIZE := Vector2(3, 1)
const BACKPACK_GRID_SIZE := Vector2(8, 7)
const JAAKARI_WEAPON_SLOT_NAME := "Weapon"
const JAAKARI_WEAPON_HINT_NAME := "JaakariWeaponHint"
const JAAKARI_WEAPON_SLOT_POSITION := Vector2(0.0, 384.0)
const SECTION_SPACING := 18.0
const SECTION_CONTAINER_NAME := "EquipmentInventorySectionContainer"
const SECTION_NAMES: Array[String] = ["Pockets", "Pants", "Jacket", "Chest Rig", "Belt", "Backpack"]
const DEFAULT_BONUS_SLOT_NAMES: Array[String] = ["Backpack", "Rig", "Torso", "Legs", "Belt"]
const FALLBACK_SLOT_BONUS_ROWS: Dictionary = {
	"Backpack": 3,
	"Rig": 2,
	"Torso": 1,
	"Legs": 1,
	"Belt": 1,
}
const SECTION_OVERLAY_NAME := "EquipmentInventorySectionsOverlay"
const STARTING_SECTION_TINT := Color(0.20, 0.60, 0.20, 0.20)
const SLOT_SECTION_TINT := Color(0.85, 0.10, 0.10, 0.12)
const STARTING_LABEL := "STARTING SLOTS"
const SECTION_SLOT_ORDER: Array[String] = ["Torso", "Rig", "Legs", "Belt", "Backpack"]

const STATE_META := "ImmersiveInventoryMod_state"

var _inventory_scroll_rows := 0
var _scrollbar_updating := false
var _gui_input_connected := false
var _equipment_known := false
var _last_equipment_signature: String = ""
var _equipment_poll_accum: float = 0.0
var _inventory_section_container: Control = null
var _inventory_section_grids: Dictionary = {}
var _last_inventory_content_bottom_y: float = MOD_VIEW_HEIGHT

func _ready() -> void:
	_last_equipment_signature = _build_equipment_signature()
	_sync_jaakari_weapon_slot()
	_sync_inventory_layout(false)

func _process(delta) -> void:
	_equipment_poll_accum += float(delta)
	if _equipment_poll_accum < 0.2:
		return

	_equipment_poll_accum = 0.0
	var signatureNow: String = _build_equipment_signature()
	if signatureNow == _last_equipment_signature:
		return

	_last_equipment_signature = signatureNow
	_sync_inventory_layout(false)

func Open():
	super()
	_sync_inventory_layout(false)

func Close():
	super()
	_reset_inventory_scroll_to_top()

func Equip(targetItem, targetSlot):
	super(targetItem, targetSlot)
	_last_equipment_signature = _build_equipment_signature()
	_sync_inventory_layout(false)

func Unequip(targetSlot):
	print("[ImmersiveInventoryMod] Unequip called for slot: %s" % [str(targetSlot)])
	var slotItem = super(targetSlot)
	_last_equipment_signature = _build_equipment_signature()
	print("[ImmersiveInventoryMod] Unequip sync immediate (signature now: %s)" % [_last_equipment_signature])
	_sync_inventory_layout(true)
	return slotItem

func LoadSlotItem(slotData, slotName):
	if slotData == null || slotData.itemData == null:
		push_warning("[ImmersiveInventoryMod] Skipped slot load (%s): missing slotData/itemData" % str(slotName))
		return

	if str(slotData.itemData.file) == "":
		push_warning("[ImmersiveInventoryMod] Skipped slot load (%s): empty item file" % str(slotName))
		return

	super(slotData, slotName)
	_last_equipment_signature = _build_equipment_signature()

	_sync_inventory_layout(false)

func LoadGridItem(slotData, targetGrid, gridPosition):
	if slotData == null || slotData.itemData == null:
		push_warning("[ImmersiveInventoryMod] Skipped grid load: missing slotData/itemData")
		return

	if str(slotData.itemData.file) == "":
		push_warning("[ImmersiveInventoryMod] Skipped grid load: empty item file")
		return

	super(slotData, targetGrid, gridPosition)

func Create(slotData, targetGrid, useDrop):
	var newItem = item.instantiate()
	newItem.slotData.Update(slotData)

	add_child(newItem)
	newItem.Initialize(self, slotData)

	# Ground pickup and other inventory creates usually target pockets.
	# Route through all active inventory containers so pickup can use section space.
	if targetGrid == inventoryGrid:
		if _try_place_in_inventory_grids(newItem):
			Reset()
			return true

		if useDrop:
			Drop(newItem)
		else:
			newItem.queue_free()
		Reset()
		return false

	if AutoPlace(newItem, targetGrid, null, useDrop):
		Reset()
		return true

	Reset()
	return false

func AutoPlace(targetItem, targetGrid, sourceGrid, usedrop):
	if targetGrid != inventoryGrid:
		return super(targetItem, targetGrid, sourceGrid, usedrop)

	if sourceGrid:
		sourceGrid.Pick(targetItem)

	if _try_place_in_inventory_grids(targetItem):
		return true

	if sourceGrid:
		sourceGrid.Place(targetItem)
		return false

	if usedrop:
		Drop(targetItem)
		return false

	targetItem.queue_free()
	Reset()
	return false

func _try_place_in_inventory_grids(targetItem) -> bool:
	for targetGrid in _get_active_inventory_target_grids():
		if _spawn_with_rotation(targetItem, targetGrid):
			return true

	return false

func _get_active_inventory_target_grids() -> Array:
	var grids: Array = []
	for sectionName in SECTION_NAMES:
		var sectionGrid: Grid = _get_or_create_section_grid(sectionName)
		if sectionGrid && sectionGrid.visible:
			grids.append(sectionGrid)

	# Last-resort backend when visible sections are full.
	if inventoryGrid:
		grids.append(inventoryGrid)

	return grids

func _spawn_with_rotation(targetItem, targetGrid) -> bool:
	if targetGrid == null:
		return false

	if targetGrid.Spawn(targetItem):
		return true

	Rotate(targetItem)
	if targetGrid.Spawn(targetItem):
		return true

	Rotate(targetItem)
	return false

func Hover():
	super()

	if hoverSlot == null:
		return

	if !_is_jaakari_weapon_slot(hoverSlot):
		return

	var draggedItemData = null
	if itemDragged && itemDragged.slotData != null:
		draggedItemData = itemDragged.slotData.itemData

	var isWeapon: bool = draggedItemData != null && str(draggedItemData.type) == "Weapon"
	if itemDragged:
		canEquip = isWeapon && hoverSlot.get_child_count() == 0
		canSlotSwap = isWeapon && hoverSlot.get_child_count() != 0
	else:
		canUnequip = hoverSlot.get_child_count() != 0

func Reset():
	super()
	_sync_inventory_scrollbar(_get_unlocked_rows())

func RefreshImmersiveInventory() -> void:
	_sync_inventory_layout(false)

func _sync_inventory_layout(forceDrop: bool) -> void:
	if inventoryUI == null || inventoryGrid == null:
		return

	var configNode = _get_config_node()
	if configNode && configNode.has_method("ReloadFromDisk"):
		configNode.ReloadFromDisk()

	_ensure_fixed_inventory_grid()
	_set_backend_inventory_visibility()
	_sync_container_layout(forceDrop)

	var unlockedRows: int = _get_unlocked_rows()
	inventoryGrid.set_meta(STATE_META, unlockedRows)
	print("[ImmersiveInventoryMod] Row sync total=%d unlocked=%d" % [_get_total_rows(), unlockedRows])

	if forceDrop:
		_drop_overflow_items(unlockedRows)

	_inventory_scroll_rows = clamp(_inventory_scroll_rows, 0, _get_max_scroll_rows())
	_sync_locked_rows_overlay(unlockedRows)
	_ensure_scrollbar()
	_sync_inventory_scrollbar(unlockedRows)
	_sync_jaakari_weapon_slot()

func _set_backend_inventory_visibility() -> void:
	if inventoryGrid == null:
		return

	# Keep vanilla grid alive as backend only.
	inventoryGrid.visible = false
	inventoryGrid.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_fixed_inventory_grid() -> void:
	if inventoryGrid == null:
		return

	if int(inventoryGrid.gridWidth) == int(POCKETS_GRID_SIZE.x) && int(inventoryGrid.gridHeight) == int(POCKETS_GRID_SIZE.y):
		return

	var inventoryItems: Array = []
	var itemPositions: Dictionary = {}
	for child in inventoryGrid.get_children():
		if child is Item:
			inventoryItems.append(child)
			itemPositions[child] = child.position

	for targetItem in inventoryItems:
		if inventoryGrid.items.has(targetItem):
			inventoryGrid.Pick(targetItem)

	inventoryGrid.CreateContainerGrid(POCKETS_GRID_SIZE)
	inventoryGrid.set_meta(STATE_META, int(POCKETS_GRID_SIZE.y))

	for targetItem in inventoryItems:
		if itemPositions.has(targetItem):
			targetItem.position = itemPositions[targetItem]

		if inventoryGrid.Place(targetItem):
			continue

		# Keep overflow items attached so the section layout can rehome them.
		continue

func _sync_container_layout(forceDrop: bool) -> void:
	if inventoryUI == null || inventoryGrid == null:
		return

	_ensure_section_container()
	var inventoryHeader: Label = inventoryUI.get_node_or_null("Header/Label")
	if inventoryHeader:
		inventoryHeader.text = "Inventory"
	var currentY: float = MOD_HEADER_HEIGHT + SECTION_SPACING
	var activeSections: Array[String] = _get_active_section_names()
	print("[ImmersiveInventoryMod] Active sections=%s" % [str(activeSections)])

	for sectionName in SECTION_NAMES:
		var isActive: bool = activeSections.has(sectionName)
		var sectionHeight: float = _layout_single_section(sectionName, isActive, Vector2(0.0, currentY), _get_section_size(sectionName))
		if sectionHeight > 0.0:
			currentY += sectionHeight + SECTION_SPACING
		elif !isActive:
			print("[ImmersiveInventoryMod] Section deactivated and hidden: %s" % [sectionName])

	_last_inventory_content_bottom_y = currentY
	_sync_jaakari_weapon_slot_position(currentY)
	_rehome_pockets_overflow()
	_resync_inventory_ui_size(currentY)
	_apply_inventory_scroll_offset()

func _ensure_section_container() -> void:
	if _inventory_section_container != null && is_instance_valid(_inventory_section_container):
		return

	_inventory_section_container = inventoryUI.get_node_or_null(SECTION_CONTAINER_NAME)
	if _inventory_section_container == null:
		_inventory_section_container = Control.new()
		_inventory_section_container.name = SECTION_CONTAINER_NAME
		_inventory_section_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inventoryUI.add_child(_inventory_section_container)
		inventoryUI.move_child(_inventory_section_container, inventoryUI.get_child_count() - 1)

func _sync_pockets_as_section() -> void:
	return

func _get_or_create_section_grid(sectionName: String) -> Grid:
	if _inventory_section_grids.has(sectionName):
		var existingGrid = _inventory_section_grids[sectionName]
		if existingGrid is Grid && is_instance_valid(existingGrid):
			return existingGrid

	if _inventory_section_container == null:
		return null

	var sectionNodeName: String = sectionName.replace(" ", "_") + "Section"
	var sectionNode: Control = _inventory_section_container.get_node_or_null(sectionNodeName)
	if sectionNode == null:
		sectionNode = Control.new()
		sectionNode.name = sectionNodeName
		sectionNode.mouse_filter = Control.MOUSE_FILTER_PASS
		_inventory_section_container.add_child(sectionNode)

	var grid: Grid = sectionNode.get_node_or_null("Grid")
	if grid == null:
		grid = Grid.new()
		grid.name = "Grid"
		grid.texture = GRID_TEXTURE
		grid.self_modulate = Color(1, 1, 1, 0.25098)
		grid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		grid.stretch_mode = TextureRect.STRETCH_TILE
		sectionNode.add_child(grid)

	var label: Label = sectionNode.get_node_or_null("Label")
	if label == null:
		label = Label.new()
		label.name = "Label"
		label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		label.theme_override_font_sizes.font_size = 13
		sectionNode.add_child(label)

	_inventory_section_grids[sectionName] = grid
	return grid

func _sync_jaakari_weapon_slot() -> void:
	var slotNode: Slot = _ensure_jaakari_weapon_slot()
	if slotNode == null:
		return

	var configNode = _get_config_node()
	var enabled: bool = true
	if configNode != null && configNode.has_method("get"):
		enabled = bool(configNode.get("jaakari_weapon_slot_enabled"))

	var shouldShow: bool = enabled && _is_jaakari_backpack_equipped()
	var targetHint: Label = _get_jaakari_weapon_hint()
	if targetHint:
		targetHint.visible = shouldShow

	if !shouldShow:
		if slotNode.get_child_count() != 0:
			for child in slotNode.get_children():
				if child is Item:
					child.reparent(self)
					_drop_item_to_ground(child)

		slotNode.visible = false
		return

	var slotSizeCells: Vector2 = Vector2(6, 2)
	if configNode != null && configNode.has_method("get_jaakari_weapon_slot_size"):
		slotSizeCells = configNode.get_jaakari_weapon_slot_size()

	var targetLocalPosition: Vector2 = _get_jaakari_weapon_local_position(slotSizeCells)
	targetLocalPosition.y -= float(_inventory_scroll_rows) * MOD_CELL_SIZE
	slotNode.visible = true
	slotNode.position = targetLocalPosition
	slotNode.size = Vector2(float(int(slotSizeCells.x)) * float(cellSize), float(int(slotSizeCells.y)) * float(cellSize))
	slotNode.custom_minimum_size = slotNode.size

	if targetHint:
		targetHint.position = targetLocalPosition + Vector2(0.0, -18.0)
		targetHint.size = slotNode.size

func _get_jaakari_weapon_local_position(slotSizeCells: Vector2) -> Vector2:
	if inventoryUI == null:
		return Vector2.ZERO

	var yPosition: float = _last_inventory_content_bottom_y + 8.0
	return Vector2(0.0, yPosition)

func _sync_jaakari_weapon_slot_position(contentBottomY: float) -> void:
	var weaponSlot: Slot = _ensure_jaakari_weapon_slot()
	if weaponSlot:
		var targetPos: Vector2 = _get_jaakari_weapon_local_position(Vector2.ONE)
		targetPos.y -= float(_inventory_scroll_rows) * MOD_CELL_SIZE
		weaponSlot.position = targetPos
		var hint: Label = weaponSlot.hint
		if hint:
			hint.position = weaponSlot.position + Vector2(0.0, -18.0)
			hint.size = weaponSlot.size

func _ensure_jaakari_weapon_slot() -> Slot:
	if inventoryUI == null:
		return null

	var slotNode: Slot = inventoryUI.get_node_or_null(JAAKARI_WEAPON_SLOT_NAME)
	if slotNode == null:
		slotNode = Slot.new()
		slotNode.name = JAAKARI_WEAPON_SLOT_NAME
		slotNode.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		slotNode.z_index = 20
		slotNode.hint = _get_jaakari_weapon_hint()
		inventoryUI.add_child(slotNode)
		inventoryUI.move_child(slotNode, inventoryUI.get_child_count() - 1)
	elif slotNode.get_parent() != inventoryUI:
		slotNode.reparent(inventoryUI)
		slotNode.z_index = 20

	return slotNode

func _get_jaakari_weapon_hint() -> Label:
	if inventoryUI == null:
		return null

	var hint: Label = inventoryUI.get_node_or_null(JAAKARI_WEAPON_HINT_NAME)
	if hint == null:
		hint = Label.new()
		hint.name = JAAKARI_WEAPON_HINT_NAME
		hint.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		hint.z_index = 21
		hint.theme_override_font_sizes.font_size = 12
		hint.text = "Weapon"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inventoryUI.add_child(hint)
		inventoryUI.move_child(hint, inventoryUI.get_child_count() - 1)
	else:
		hint.z_index = 21

	return hint

func _is_jaakari_weapon_slot(slotNode) -> bool:
	return slotNode != null && str(slotNode.name) == JAAKARI_WEAPON_SLOT_NAME

func _layout_single_section(sectionName: String, sectionVisible: bool, sectionPosition: Vector2, sectionSize: Vector2) -> float:
	var sectionGrid: Grid = _get_or_create_section_grid(sectionName)
	if sectionGrid == null:
		return 0.0

	sectionGrid.visible = sectionVisible
	sectionGrid.set_meta("inventory_section", sectionName)

	var sectionNode: Control = sectionGrid.get_parent() as Control
	if !sectionVisible:
		print("[ImmersiveInventoryMod] >>> Section HIDE START: %s" % [sectionName])
		_evict_section_items(sectionGrid)
		if sectionNode:
			sectionNode.visible = false
			print("[ImmersiveInventoryMod] >>> Section node.visible=false: %s" % [sectionName])
		else:
			print("[ImmersiveInventoryMod] >>> ERROR: Section node is null for: %s" % [sectionName])
		print("[ImmersiveInventoryMod] >>> Section HIDE END: %s" % [sectionName])
		return 0.0

	if int(sectionGrid.gridWidth) != int(sectionSize.x) || int(sectionGrid.gridHeight) != int(sectionSize.y):
		var sectionItems: Array = []
		for child in sectionGrid.get_children():
			if child is Item:
				sectionItems.append(child)

		for itemNode in sectionItems:
			if sectionGrid.items.has(itemNode):
				sectionGrid.Pick(itemNode)

		sectionGrid.CreateContainerGrid(sectionSize)

		for itemNode in sectionItems:
			if !AutoPlace(itemNode, sectionGrid, null, false):
				_drop_item_to_ground(itemNode)

	if sectionNode:
		sectionNode.visible = true
		sectionNode.position = sectionPosition
		sectionNode.size = sectionGrid.size

	sectionGrid.position = Vector2.ZERO

	var header: Label = _get_or_create_section_label(sectionName, sectionGrid)
	header.position = Vector2(0.0, -18.0)
	header.text = _get_section_label_text(sectionName)

	return float(int(sectionGrid.gridHeight) * int(sectionGrid.cellSize))

func _get_or_create_section_label(sectionName: String, sectionGrid: Grid) -> Label:
	var sectionNode: Control = sectionGrid.get_parent() as Control
	if sectionNode == null:
		return Label.new()

	var label: Label = sectionNode.get_node_or_null("Label")
	if label == null:
		label = Label.new()
		label.name = "Label"
		label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		label.theme_override_font_sizes.font_size = 13
		sectionNode.add_child(label)

	return label

func _get_section_size(sectionName: String) -> Vector2:
	match sectionName:
		"Pants":
			return PANTS_GRID_SIZE
		"Jacket":
			return JACKET_GRID_SIZE
		"Chest Rig":
			return _get_dynamic_rig_size()
		"Belt":
			return BELT_GRID_SIZE
		"Backpack":
			return _get_dynamic_backpack_size()
		_:
			return POCKETS_GRID_SIZE

func _get_dynamic_backpack_size() -> Vector2:
	var itemData = _get_equipped_item_data("Backpack")
	if itemData == null:
		return BACKPACK_GRID_SIZE

	var configNode = _get_config_node()
	if configNode != null && configNode.has_method("get_backpack_rows_for_item"):
		var rows: int = int(configNode.get_backpack_rows_for_item(itemData))
		return Vector2(BACKPACK_GRID_SIZE.x, clamp(rows, 1, MAX_ALLOWED_ROWS))

	if str(itemData.file).find("Backpack_Jaeger") != -1:
		return BACKPACK_GRID_SIZE

	return Vector2(BACKPACK_GRID_SIZE.x, 5)

func _get_dynamic_rig_size() -> Vector2:
	var itemData = _get_equipped_item_data("Rig")
	if itemData == null:
		return CHEST_RIG_GRID_SIZE

	var configNode = _get_config_node()
	if configNode != null && configNode.has_method("get_rig_rows_for_item"):
		var rows: int = int(configNode.get_rig_rows_for_item(itemData))
		return Vector2(CHEST_RIG_GRID_SIZE.x, clamp(rows, 1, MAX_ALLOWED_ROWS))

	if str(itemData.file).find("Vest_Fishing") != -1:
		return Vector2(CHEST_RIG_GRID_SIZE.x, 1)

	return CHEST_RIG_GRID_SIZE

func _get_equipped_item_data(slotName: String):
	var slotNode = _find_equipment_slot(slotName)
	if slotNode == null:
		return null

	for child in slotNode.get_children():
		if child is Item && child.slotData != null && child.slotData.itemData != null:
			return child.slotData.itemData

	return null

func _is_jaakari_backpack_equipped() -> bool:
	var itemData = _get_equipped_item_data("Backpack")
	if itemData == null:
		return false

	return str(itemData.file).find("Backpack_Jaeger") != -1

func _get_section_label_text(sectionName: String) -> String:
	var equippedName: String = _get_equipped_slot_display_name(sectionName)
	if equippedName != "":
		return "%s - %s" % [sectionName, equippedName]
	return sectionName

func _get_equipped_slot_display_name(sectionName: String) -> String:
	var slotName: String = sectionName
	if sectionName == "Chest Rig":
		slotName = "Rig"
	elif sectionName == "Jacket":
		slotName = "Torso"
	elif sectionName == "Pants":
		slotName = "Legs"

	var slotNode = _find_equipment_slot(slotName)
	if slotNode == null:
		return ""

	for child in slotNode.get_children():
		if child is Item && child.slotData != null && child.slotData.itemData != null:
			return str(child.slotData.itemData.display)

	return ""

func _get_active_section_names() -> Array[String]:
	var names: Array[String] = []
	names.append("Pockets")
	if _slot_has_equipped_item("Legs"):
		names.append("Pants")
	if _slot_has_equipped_item("Torso"):
		names.append("Jacket")
	if _slot_has_equipped_item("Rig"):
		names.append("Chest Rig")
	if _slot_has_equipped_item("Belt"):
		names.append("Belt")
	if _slot_has_equipped_item("Backpack"):
		names.append("Backpack")

	return names

func _resync_inventory_ui_size(contentBottomY: float) -> void:
	var targetHeight: float = max(MOD_VIEW_HEIGHT, contentBottomY + 24.0)
	if inventoryGrid != null:
		inventoryGrid.custom_minimum_size = Vector2(float(BASE_WIDTH) * MOD_CELL_SIZE, targetHeight - MOD_HEADER_HEIGHT)
		inventoryGrid.size = Vector2(float(BASE_WIDTH) * MOD_CELL_SIZE, targetHeight - MOD_HEADER_HEIGHT)
	if _inventory_section_container != null:
		_inventory_section_container.custom_minimum_size = Vector2(MOD_VIEW_WIDTH, max(0.0, targetHeight - MOD_HEADER_HEIGHT))

	print("[ImmersiveInventoryMod] UI height sync: contentBottomY=%.0f -> targetHeight=%.0f" % [contentBottomY, targetHeight])

func _rehome_pockets_overflow() -> void:
	if inventoryGrid == null:
		return

	var activeSectionGrids: Array[Grid] = []
	for sectionName in SECTION_NAMES:
		var grid: Grid = _get_or_create_section_grid(sectionName)
		if grid && grid.visible:
			activeSectionGrids.append(grid)

	var pocketItems: Array = []
	for child in inventoryGrid.get_children():
		if child is Item:
			pocketItems.append(child)

	for pocketItem in pocketItems:
		if inventoryGrid.items.has(pocketItem):
			continue

		var placed: bool = false
		for sectionGrid in activeSectionGrids:
			if AutoPlace(pocketItem, sectionGrid, inventoryGrid, false):
				placed = true
				break

		if !placed:
			print("[ImmersiveInventoryMod] Overflow drop from Pockets: %s" % [str(pocketItem.name)])
			if inventoryGrid.items.has(pocketItem):
				inventoryGrid.Pick(pocketItem)
			_drop_item_to_ground(pocketItem)

func _evict_section_items(sectionGrid: Grid) -> void:
	if sectionGrid == null:
		return

	var itemsToDrop: Array = []
	for child in sectionGrid.get_children():
		if child is Item:
			itemsToDrop.append(child)

	if itemsToDrop.size() == 0:
		print("[ImmersiveInventoryMod]   Evict: section was empty")
		return

	print("[ImmersiveInventoryMod]   Evict: processing %d items" % [itemsToDrop.size()])
	var droppedCount: int = 0
	for itemNode in itemsToDrop:
		if sectionGrid.items.has(itemNode):
			sectionGrid.Pick(itemNode)
			droppedCount += 1
			print("[ImmersiveInventoryMod]   Evict: dropped %s" % [str(itemNode.name)])
		else:
			print("[ImmersiveInventoryMod]   Evict: item not in grid dict, dropping anyway: %s" % [str(itemNode.name)])

		_drop_item_to_ground(itemNode)

	print("[ImmersiveInventoryMod]   Evict: total dropped=%d" % [droppedCount])

func _get_unlocked_rows() -> int:
	var configNode = _get_config_node()
	if configNode == null:
		return _get_fallback_unlocked_rows()

	if !configNode.has_method("get_bonus_rows_for_slot") || !configNode.has_method("get_total_rows"):
		return _get_fallback_unlocked_rows()

	if !bool(configNode.enabled) || !bool(configNode.compact_mode):
		return clamp(int(configNode.get_total_rows()), BASE_ROWS, MAX_ALLOWED_ROWS)

	var unlockedRows: int = BASE_ROWS + int(configNode.extra_rows)
	for slotName in _get_bonus_slot_names(configNode):
		if _slot_has_equipped_item(slotName):
			unlockedRows += int(configNode.get_bonus_rows_for_slot(slotName))

	return clamp(unlockedRows, BASE_ROWS, MAX_ALLOWED_ROWS)

func _get_fallback_unlocked_rows() -> int:
	var unlockedRows: int = BASE_ROWS
	for slotName in DEFAULT_BONUS_SLOT_NAMES:
		if _slot_has_equipped_item(slotName):
			unlockedRows += int(FALLBACK_SLOT_BONUS_ROWS.get(slotName, 0))

	return clamp(unlockedRows, BASE_ROWS, MAX_ALLOWED_ROWS)

func _slot_has_equipped_item(slotName: String) -> bool:
	if equipment == null:
		return false

	var slotNode = _find_equipment_slot(slotName)
	if slotNode:
		for child in slotNode.get_children():
			if child is Item:
				_equipment_known = true
				return true

			for nested in child.get_children():
				if nested is Item:
					_equipment_known = true
					return true

	for child in get_children():
		if child is Item && bool(child.equipped) && child.equipSlot != null && str(child.equipSlot.name) == slotName:
			_equipment_known = true
			return true

	return false

func _find_equipment_slot(slotName: String):
	if equipment == null:
		return null

	for slot in equipment.get_children():
		if str(slot.name) == slotName:
			return slot

	return null

func _get_bonus_slot_names(configNode) -> Array[String]:
	if configNode != null:
		var configuredSlots = configNode.get("slot_bonus_rows")
		if configuredSlots is Dictionary && configuredSlots.size() != 0:
			var names: Array[String] = []
			for key in configuredSlots.keys():
				names.append(str(key))
			return names

	return DEFAULT_BONUS_SLOT_NAMES

func _build_equipment_signature() -> String:
	if equipment == null:
		return "none"

	var parts: Array[String] = []
	for slotName in _get_bonus_slot_names(_get_config_node()):
		parts.append("%s=%d" % [slotName, int(_slot_has_equipped_item(slotName))])

	return "|".join(parts)

func _get_total_rows() -> int:
	return _get_unlocked_rows()

func _get_config_node():
	var root = get_tree().root
	if root == null:
		return null

	var node = root.get_node_or_null(CONFIG_NODE_PATH)
	if node:
		return node

	node = root.get_node_or_null("ImmersiveInventoryConfig")
	if node:
		return node

	# ModLoader can suffix autoload names; detect by capabilities instead of exact name.
	for child in root.get_children():
		if child == null:
			continue

		if child.has_method("get_total_rows") && child.has_method("get_bonus_rows_for_slot"):
			if child.has_method("ReloadFromDisk") || child.has_method("UpdateConfigProperties"):
				return child

	return null

func GetInventoryGrids() -> Array:
	var grids: Array = []
	for sectionName in SECTION_NAMES:
		var sectionGrid: Grid = _get_or_create_section_grid(sectionName)
		if sectionGrid && sectionGrid.visible:
			grids.append(sectionGrid)

	return grids

func GetInventorySectionGrid(sectionName: String):
	var sectionGrid: Grid = _get_or_create_section_grid(sectionName)
	if sectionGrid && sectionGrid.visible:
		return sectionGrid

	return null

func GetHoverItem():
	var contextVisible: bool = context != null && context.visible

	if containerGrid && containerGrid.is_visible_in_tree():
		for element in containerGrid.get_children():
			if element.get_global_rect().has_point(mousePosition) && element is Item && element != itemDragged && !contextVisible:
				return element

	if catalogGrid && catalogGrid.is_visible_in_tree():
		for element in catalogGrid.get_children():
			if element.get_global_rect().has_point(mousePosition) && element is Item && element != itemDragged && !contextVisible:
				return element

	if supplyGrid && supplyGrid.is_visible_in_tree():
		for element in supplyGrid.get_children():
			if element.get_global_rect().has_point(mousePosition) && element is Item && element != itemDragged && !contextVisible:
				return element

	for sectionName in SECTION_NAMES:
		var sectionGrid: Grid = _get_or_create_section_grid(sectionName)
		if sectionGrid == null || !sectionGrid.visible || !sectionGrid.is_visible_in_tree():
			continue

		for element in sectionGrid.get_children():
			if element.get_global_rect().has_point(mousePosition) && element is Item && element != itemDragged && !contextVisible:
				return element

	return null

func GetHoverGrid():
	var grids: Array = []
	if containerGrid:
		grids.append(containerGrid)
	if catalogGrid:
		grids.append(catalogGrid)
	if supplyGrid:
		grids.append(supplyGrid)
	for sectionName in SECTION_NAMES:
		var sectionGrid: Grid = _get_or_create_section_grid(sectionName)
		if sectionGrid && sectionGrid.visible:
			grids.append(sectionGrid)

	for grid in grids:
		if grid && grid.is_visible_in_tree() and grid.get_global_rect().has_point(mousePosition) and grid is Grid:
			return grid

	return null

func GetHoverSlot():
	var customSlot: Slot = _get_inventory_weapon_hover_slot()
	if customSlot != null:
		return customSlot

	return super()

func _get_inventory_weapon_hover_slot() -> Slot:
	var slotNode: Slot = _get_inventory_weapon_slot()
	if slotNode == null || !slotNode.visible || !slotNode.is_visible_in_tree():
		return null

	if slotNode.get_global_rect().has_point(mousePosition):
		return slotNode

	return null

func _get_inventory_weapon_slot() -> Slot:
	if inventoryUI == null:
		return null

	var slotNode: Control = inventoryUI.get_node_or_null(JAAKARI_WEAPON_SLOT_NAME)
	if slotNode is Slot:
		return slotNode

	return null

func _ensure_scrollbar() -> void:
	var scrollbar = inventoryUI.get_node_or_null(MOD_SCROLLBAR_NAME)

	if scrollbar == null:
		scrollbar = VScrollBar.new()
		scrollbar.name = MOD_SCROLLBAR_NAME
		scrollbar.theme = GAME_UI_THEME
		scrollbar.mouse_filter = Control.MOUSE_FILTER_STOP
		scrollbar.step = MOD_CELL_SIZE
		scrollbar.page = MOD_VIEW_HEIGHT
		scrollbar.custom_minimum_size = Vector2(MOD_SCROLLBAR_WIDTH, MOD_VIEW_HEIGHT)
		inventoryUI.add_child(scrollbar)
		scrollbar.value_changed.connect(_on_inventory_scrollbar_changed)

	scrollbar.position = Vector2(MOD_VIEW_WIDTH + MOD_SCROLLBAR_GAP, MOD_HEADER_HEIGHT)
	scrollbar.size = Vector2(MOD_SCROLLBAR_WIDTH, MOD_VIEW_HEIGHT)
	scrollbar.visible = _get_scrollbar_total_content_height() > _get_scrollbar_viewport_height()
	scrollbar.min_value = 0.0
	scrollbar.max_value = _get_scrollbar_total_content_height()
	scrollbar.page = _get_scrollbar_viewport_height()
	scrollbar.step = MOD_CELL_SIZE

func _sync_inventory_scrollbar(unlockedRows: int) -> void:
	var scrollbar = inventoryUI.get_node_or_null(MOD_SCROLLBAR_NAME)
	if !scrollbar:
		return

	var maxScrollRows: int = _get_max_scroll_rows()
	if maxScrollRows == 0:
		scrollbar.visible = false
		_scrollbar_updating = true
		scrollbar.value = 0.0
		_scrollbar_updating = false
		return

	var currentScrollPixels: float = float(_inventory_scroll_rows * int(MOD_CELL_SIZE))
	scrollbar.visible = true
	_scrollbar_updating = true
	scrollbar.min_value = 0.0
	scrollbar.max_value = _get_scrollbar_total_content_height()
	scrollbar.page = _get_scrollbar_viewport_height()
	scrollbar.step = MOD_CELL_SIZE
	scrollbar.value = currentScrollPixels
	_scrollbar_updating = false

func _on_inventory_scrollbar_changed(value):
	if _scrollbar_updating:
		return

	var maxScroll: float = max(0.0, _get_scrollbar_total_content_height() - _get_scrollbar_viewport_height())
	var clampedValue: float = clamp(float(value), 0.0, maxScroll)
	_inventory_scroll_rows = int(round(clampedValue / MOD_CELL_SIZE))
	_apply_inventory_scroll_offset()
	_sync_inventory_scrollbar(_get_unlocked_rows())

func _get_scrollbar_viewport_height() -> float:
	return MOD_VIEW_HEIGHT

func _get_scrollbar_total_content_height() -> float:
	return max(MOD_VIEW_HEIGHT, _last_inventory_content_bottom_y)

func _handle_inventory_wheel_input(event) -> void:
	if event is not InputEventMouseButton || !event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if ModScrollInventory(-MOD_CELL_SIZE):
			get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if ModScrollInventory(MOD_CELL_SIZE):
			get_viewport().set_input_as_handled()

func _on_inventory_gui_input(event) -> void:
	_handle_inventory_wheel_input(event)

func _unhandled_input(event) -> void:
	_handle_inventory_wheel_input(event)

func _reset_inventory_scroll_to_top() -> void:
	_inventory_scroll_rows = 0
	_apply_inventory_scroll_offset()

	var scrollbar = inventoryUI.get_node_or_null(MOD_SCROLLBAR_NAME)
	if scrollbar:
		_scrollbar_updating = true
		scrollbar.value = 0.0
		_scrollbar_updating = false

func ModScrollInventory(step: float) -> bool:
	if inventoryUI == null:
		return false

	var viewRect: Rect2 = Rect2(
		inventoryUI.global_position + Vector2(0.0, MOD_HEADER_HEIGHT),
		Vector2(MOD_VIEW_WIDTH, MOD_VIEW_HEIGHT)
	)
	if !viewRect.has_point(get_global_mouse_position()):
		return false

	var newScrollRows: int = int(_inventory_scroll_rows + (step / MOD_CELL_SIZE))
	newScrollRows = clamp(newScrollRows, 0, _get_max_scroll_rows())

	if newScrollRows == _inventory_scroll_rows:
		return false

	_inventory_scroll_rows = newScrollRows
	_apply_inventory_scroll_offset()
	_sync_inventory_scrollbar(_get_unlocked_rows())
	return true

func _apply_inventory_scroll_offset() -> void:
	if inventoryGrid == null || _inventory_section_container == null:
		return
	
	var offsetY: float = -(float(_inventory_scroll_rows) * MOD_CELL_SIZE)
	
	# Scroll Pockets grid up
	inventoryGrid.position.y = MOD_HEADER_HEIGHT + offsetY
	
	# Section nodes are already laid out with absolute Y in _sync_container_layout,
	# so only apply scroll delta here to avoid adding the base offset twice.
	_inventory_section_container.position.y = offsetY

	# Keep Jaakari slot synced with the same scroll transform.
	_sync_jaakari_weapon_slot_position(_last_inventory_content_bottom_y)

func _get_max_scroll_rows() -> int:
	var totalContentHeight: float = 0.0
	var activeSectionNames: Array[String] = _get_active_section_names()
	
	for sectionName in activeSectionNames:
		var sectionSize: Vector2 = _get_section_size(sectionName)
		totalContentHeight += float(int(sectionSize.y) * int(MOD_CELL_SIZE)) + SECTION_SPACING
	
	var viewportHeight: float = MOD_VIEW_HEIGHT - MOD_HEADER_HEIGHT - float(int(inventoryGrid.gridHeight) * int(inventoryGrid.cellSize)) - SECTION_SPACING
	var maxScroll: int = int(max(0.0, totalContentHeight - viewportHeight) / MOD_CELL_SIZE)
	return maxScroll

func _drop_overflow_items(unlockedRows: int) -> void:
	var overflowItems: Array = []

	for child in inventoryGrid.get_children():
		if !child is Item:
			continue

		var gridPosition = inventoryGrid.GetGridPosition(child.global_position + Vector2(float(inventoryGrid.cellSize) / 2.0, float(inventoryGrid.cellSize) / 2.0))
		var gridSize = inventoryGrid.GetGridSize(child)

		if int(gridPosition.y) + int(gridSize.y) > unlockedRows:
			overflowItems.append(child)

	for targetItem in overflowItems:
		if inventoryGrid.items.has(targetItem):
			inventoryGrid.Pick(targetItem)
		_drop_item_to_ground(targetItem)

func _drop_item_to_ground(target) -> void:
	var map = get_tree().current_scene.get_node_or_null("/root/Map")
	if !map || !target || !target.slotData || !target.slotData.itemData:
		if target:
			if target.get_parent() == inventoryGrid:
				inventoryGrid.remove_child(target)
			target.queue_free()
		return

	var file = Database.get(target.slotData.itemData.file)
	if !file:
		if target.get_parent() == inventoryGrid:
			inventoryGrid.remove_child(target)
		target.queue_free()
		return

	var dropDirection: Vector3 = -camera.global_transform.basis.z
	var dropPosition: Vector3 = (camera.global_position + Vector3(0, -0.25, 0)) + dropDirection / 2.0
	var dropRotation: Vector3 = Vector3(-25, camera.rotation_degrees.y + 180 + randf_range(-45, 45), 45)
	var dropForce: float = 2.5

	if target.slotData.itemData.stackable:
		var boxSize: int = int(target.slotData.itemData.defaultAmount)
		var boxesNeeded: int = ceil(float(target.slotData.amount) / float(boxSize))
		var amountLeft: int = int(target.slotData.amount)

		for _box in range(boxesNeeded):
			var pickup = file.instantiate()
			map.add_child(pickup)
			pickup.position = dropPosition
			pickup.rotation_degrees = dropRotation
			pickup.linear_velocity = dropDirection * dropForce
			pickup.Unfreeze()

			var newSlotData: SlotData = SlotData.new()
			newSlotData.itemData = target.slotData.itemData

			if amountLeft > boxSize:
				amountLeft -= boxSize
				newSlotData.amount = boxSize
			else:
				newSlotData.amount = amountLeft

			pickup.slotData.Update(newSlotData)
	else:
		var pickup = file.instantiate()
		map.add_child(pickup)
		pickup.position = dropPosition
		pickup.rotation_degrees = dropRotation
		pickup.linear_velocity = dropDirection * dropForce
		pickup.Unfreeze()
		pickup.slotData.Update(target.slotData)
		pickup.UpdateAttachments()

	if target.get_parent() == inventoryGrid:
		inventoryGrid.remove_child(target)
	target.queue_free()
	PlayDrop()
	UpdateStats(true)

func UpdateStats(updateLabels: bool):
	await get_tree().physics_frame

	currentInventoryCapacity = 0.0
	currentInventoryWeight = 0.0
	currentInventoryValue = 0.0
	currentEquipmentValue = 0.0
	currentContainerWeight = 0.0
	currentContainerValue = 0.0
	currentEquipmentWeight = 0.0
	currentEquipmentValue = 0.0
	currentEquipmentInsulation = 0.0
	currentSupplyValue = 0.0
	inventoryWeightPercentage = 0.0

	for equipmentSlot in equipment.get_children():
		if equipmentSlot is Slot && equipmentSlot.get_child_count() != 0:
			currentEquipmentWeight += equipmentSlot.get_child(0).Weight()
			currentEquipmentValue += equipmentSlot.get_child(0).Value()
			currentInventoryCapacity += equipmentSlot.get_child(0).slotData.itemData.capacity
			currentEquipmentInsulation += equipmentSlot.get_child(0).slotData.itemData.insulation

	currentInventoryCapacity += baseCarryWeight
	insulationMultiplier = 1.0 - (currentEquipmentInsulation / 100.0)
	character.insulation = insulationMultiplier

	for gridNode in GetInventoryGrids():
		if gridNode == null || !gridNode.visible:
			continue

		for element in gridNode.get_children():
			if element is Item:
				currentInventoryWeight += element.Weight()
				currentInventoryValue += element.Value()

	if currentInventoryWeight > currentInventoryCapacity:
		if !gameData.overweight:
			character.Overweight(true)
	else:
		character.Overweight(false)

	var combinedWeight = currentInventoryWeight + currentEquipmentWeight
	if combinedWeight > 20:
		character.heavyGear = true
	else:
		character.heavyGear = false

	if container:
		for element in containerGrid.get_children():
			currentContainerWeight += element.Weight()
			currentContainerValue += element.Value()

	if trader:
		for element in supplyGrid.get_children():
			currentSupplyValue += element.Value()

	if updateLabels:
		inventoryWeightPercentage = currentInventoryWeight / max(1.0, currentInventoryCapacity)
		inventoryCapacity.text = str("%.1f" % currentInventoryCapacity)
		inventoryWeight.text = str("%.1f" % currentInventoryWeight)
		inventoryValue.text = str(int(round(currentInventoryValue)))

		if inventoryWeightPercentage > 1:
			inventoryWeight.modulate = Color.RED
		elif inventoryWeightPercentage >= 0.5:
			inventoryWeight.modulate = Color.YELLOW
		else:
			inventoryWeight.modulate = Color.GREEN

		equipmentCapacity.text = str(int(round(currentInventoryCapacity))) + "kg"
		equipmentValue.text = str(int(round(currentEquipmentValue)))
		equipmentInsulation.text = str(int(round(currentEquipmentInsulation)))

		if currentEquipmentInsulation <= 25:
			equipmentInsulation.modulate = Color.RED
		elif currentEquipmentInsulation <= 50:
			equipmentInsulation.modulate = Color.YELLOW
		else:
			equipmentInsulation.modulate = Color.GREEN

		if container:
			containerWeight.text = str("%.1f" % currentContainerWeight)
			containerValue.text = str(int(round(currentContainerValue)))
		if trader:
			supplyValue.text = str(int(round(currentSupplyValue)))

func _sync_locked_rows_overlay(unlockedRows: int) -> void:
	# Keep the layout readable without introducing extra nodes under inventoryGrid.
	return

func _sync_slot_container_overlay(unlockedRows: int) -> void:
	if inventoryGrid == null:
		return

	var cellSize: float = float(int(inventoryGrid.cellSize))
	var gridCols: int = int(inventoryGrid.gridWidth)
	var gridRows: int = int(inventoryGrid.gridHeight)
	var overlay: Control = inventoryGrid.get_node_or_null(SECTION_OVERLAY_NAME)
	if overlay == null:
		overlay = Control.new()
		overlay.name = SECTION_OVERLAY_NAME
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inventoryGrid.add_child(overlay)
		inventoryGrid.move_child(overlay, 0)

	overlay.position = Vector2.ZERO
	overlay.size = Vector2(float(gridCols) * cellSize, float(gridRows) * cellSize)

	for child in overlay.get_children():
		child.queue_free()

	_add_section_visual(overlay, 0, 0, gridCols, BASE_ROWS, STARTING_LABEL, STARTING_SECTION_TINT)

	var slotRowsByName: Dictionary = _get_active_slot_rows_by_name(unlockedRows)
	var rowCursor: int = BASE_ROWS + _get_effective_extra_rows()
	var pantsRows: int = int(slotRowsByName.get("Legs", 0))
	var jacketRows: int = int(slotRowsByName.get("Torso", 0))
	var vestRows: int = int(slotRowsByName.get("Rig", 0))
	var beltRows: int = int(slotRowsByName.get("Belt", 0))
	var backpackRows: int = int(slotRowsByName.get("Backpack", 0))

	var pantsCols: int = clamp(3, 1, max(1, gridCols - 1))
	var jacketCols: int = max(1, gridCols - pantsCols)
	var topPocketRows: int = max(pantsRows, jacketRows)
	if topPocketRows > 0:
		_add_section_visual(overlay, 0, rowCursor, pantsCols, max(1, pantsRows), _get_equipped_slot_label("Legs", "PANTS"), SLOT_SECTION_TINT)
		_add_section_visual(overlay, pantsCols, rowCursor, jacketCols, max(1, jacketRows), _get_equipped_slot_label("Torso", "JACKET"), SLOT_SECTION_TINT)
		rowCursor += topPocketRows

	if vestRows > 0:
		_add_section_visual(overlay, 0, rowCursor, gridCols, vestRows, _get_equipped_slot_label("Rig", "VEST"), SLOT_SECTION_TINT)
		rowCursor += vestRows

	var beltCols: int = clamp(3, 1, gridCols)
	if beltRows > 0:
		_add_section_visual(overlay, 0, rowCursor, beltCols, beltRows, _get_equipped_slot_label("Belt", "BELT"), SLOT_SECTION_TINT)
		rowCursor += beltRows

	if backpackRows > 0:
		_add_section_visual(overlay, 0, rowCursor, gridCols, backpackRows, _get_equipped_slot_label("Backpack", "BACKPACK"), SLOT_SECTION_TINT)

func _add_section_visual(parent: Control, startCol: int, startRow: int, colCount: int, rowCount: int, labelText: String, tint: Color) -> void:
	if colCount <= 0 || rowCount <= 0:
		return

	var cellSize: float = float(int(inventoryGrid.cellSize))
	var section := Panel.new()
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.position = Vector2(float(startCol) * cellSize, float(startRow) * cellSize)
	section.size = Vector2(float(colCount) * cellSize, float(rowCount) * cellSize)

	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = Color(1.0, 0.0, 0.0, 0.95)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	section.add_theme_stylebox_override("panel", style)
	parent.add_child(section)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = labelText.to_upper()
	label.position = Vector2(8.0, -18.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.modulate = Color(0.05, 0.10, 0.80, 1.0)
	parent.add_child(label)

func _get_active_slot_rows_by_name(unlockedRows: int) -> Dictionary:
	var slotRowsByName: Dictionary = {}
	for slotName in DEFAULT_BONUS_SLOT_NAMES:
		slotRowsByName[slotName] = 0

	var configNode = _get_config_node()
	if configNode != null && bool(configNode.enabled) && bool(configNode.compact_mode):
		for slotName in _get_bonus_slot_names(configNode):
			if _slot_has_equipped_item(slotName):
				slotRowsByName[slotName] = int(configNode.get_bonus_rows_for_slot(slotName))
	else:
		for slotName in DEFAULT_BONUS_SLOT_NAMES:
			if _slot_has_equipped_item(slotName):
				slotRowsByName[slotName] = int(FALLBACK_SLOT_BONUS_ROWS.get(slotName, 0))

	var maxRowsForSlots: int = max(0, unlockedRows - BASE_ROWS - _get_effective_extra_rows())
	var usedRows: int = 0
	for slotName in SECTION_SLOT_ORDER:
		if usedRows >= maxRowsForSlots:
			slotRowsByName[slotName] = 0
			continue

		var rows: int = int(slotRowsByName.get(slotName, 0))
		rows = clamp(rows, 0, maxRowsForSlots - usedRows)
		slotRowsByName[slotName] = rows
		usedRows += rows

	return slotRowsByName

func _get_equipped_slot_label(slotName: String, sectionTitle: String) -> String:
	var slotNode = _find_equipment_slot(slotName)
	if slotNode:
		for child in slotNode.get_children():
			if child is Item && child.slotData != null && child.slotData.itemData != null:
				var displayName: String = str(child.slotData.itemData.display)
				if displayName != "":
					return "%s - %s" % [sectionTitle, displayName]

	return "%s" % sectionTitle

func _get_effective_extra_rows() -> int:
	var configNode = _get_config_node()
	if configNode == null:
		return 0

	if !bool(configNode.enabled):
		return 0

	return max(0, int(configNode.extra_rows))

func _sanitize_inventory_highlight() -> void:
	if !highlight || !highlight.visible:
		return

	if highlight.get_parent() == inventoryGrid:
		return

	if highlight.get_parent() != null:
		highlight.reparent(inventoryGrid)

