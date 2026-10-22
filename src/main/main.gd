class_name Main
extends Control
## WP0 stub so CI can boot the main scene. WP4 replaces this file (docs/DESIGN.md G.3).


func _ready() -> void:
	InputSetup.ensure_actions()
