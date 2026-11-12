class_name ItemRoll
extends RefCounted
## Position-weighted item roll (host only). The leader mostly gets defensive
## items (banana, mud), racers at the back more turbos and punches: a
## comeback chance without guaranteeing anything.


## Weights in ItemKind.ALL order for race position `position` of `count`.
static func weights_for(config: ItemConfig, position: int, count: int) -> PackedFloat32Array:
	var t := 0.0 if count <= 1 else clampf(float(position - 1) / float(count - 1), 0.0, 1.0)
	var out := PackedFloat32Array()
	for i in ItemKind.ALL.size():
		var front := config.leader_weights[i] if i < config.leader_weights.size() else 1.0
		var back := config.last_weights[i] if i < config.last_weights.size() else 1.0
		out.append(maxf(lerpf(front, back, t), 0.0))
	return out


static func roll(rng: RandomNumberGenerator, config: ItemConfig, position: int, count: int) -> ItemKind.Kind:
	var weights := weights_for(config, position, count)
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return ItemKind.ALL[rng.randi() % ItemKind.ALL.size()]
	var pick := rng.randf() * total
	for i in weights.size():
		pick -= weights[i]
		if pick < 0.0:
			return ItemKind.ALL[i]
	return ItemKind.ALL[-1]
