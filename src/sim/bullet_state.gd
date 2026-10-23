class_name BulletState
extends RefCounted
## One flying bullet (D.4).

var id: int = 0
var spec: BulletSpec
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var pierce_left: int = 0
var life: float = 0.0
var hit_ids: Dictionary[int, bool] = {}   # enemies already hit: each is hit at most once
