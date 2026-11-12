class_name MapSelectScreen
extends MenuScreen
## Reusable map picker: one card per map in MapCatalog. Selecting a card
## marks it; Continue reports it through `on_chosen` (set by whoever opened
## the screen: new solo race or the lobby's Change Map).

var cards: Array[MapCard] = []
var selected_id := MapCatalog.DEFAULT_MAP
## Called with the chosen map id.
var on_chosen := Callable()
var continue_button: Button


func build() -> void:
	var column := make_page("CHOOSE A MAP", "Three downhill races: pick one. The route map shows each course from start to finish.")
	var row := UiKit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for map in MapCatalog.get_maps():
		var card := MapCard.new()
		card.setup(map)
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card.pressed.connect(select.bind(map.id))
		row.add_child(card)
		cards.append(card)
	var footer := UiKit.hbox(16)
	column.add_child(footer)
	make_back_button(footer)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fill)
	continue_button = UiKit.button("Continue", "primary", 260)
	continue_button.pressed.connect(confirm)
	footer.add_child(continue_button)


func on_enter() -> void:
	select(selected_id)


func select(map_id: String) -> void:
	var map := MapCatalog.get_map(map_id)
	if map == null or not map.is_playable():
		return
	selected_id = map_id
	for card in cards:
		card.selected = card.map.id == map_id
	continue_button.disabled = false


func confirm() -> void:
	if on_chosen.is_valid():
		on_chosen.call(selected_id)


func get_default_focus() -> Control:
	for card in cards:
		if card.selected:
			return card
	return continue_button
