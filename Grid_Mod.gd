extends "res://Scripts/Grid.gd"

const MAX_ALLOWED_ROWS := 34

func CreateContainerGrid(containerSize: Vector2):
	containerSize.x = clamp(containerSize.x, 1, 8)
	containerSize.y = clamp(containerSize.y, 1, MAX_ALLOWED_ROWS)

	gridWidth = containerSize.x
	gridHeight = containerSize.y

	var gridSize = Vector2(containerSize.x * cellSize, containerSize.y * cellSize)
	custom_minimum_size = gridSize
	size = gridSize

	grid.clear()
	items.clear()

	for x in range(gridWidth):
		grid[x] = {}
		for y in range(gridHeight):
			grid[x][y] = false
