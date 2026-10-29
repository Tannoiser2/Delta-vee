extends SceneTree
func _init() -> void:
	for p in ["res://scripts/ui/ui.gd", "res://scripts/ui/timeline.gd", "res://scripts/ui/board_2d.gd", "res://scripts/ui/board_3d.gd", "res://scripts/ui/game_view.gd", "res://scripts/ui/menu.gd", "res://scripts/ui/rules_view.gd", "res://scripts/ui/main.gd", "res://scripts/net/net.gd", "res://scripts/net/online_session.gd"]:
		var s = load(p)
		print(p, " ", s != null and s.can_instantiate())
	quit()
