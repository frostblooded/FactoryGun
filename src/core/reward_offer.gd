class_name RewardOffer
extends RefCounted
## One reward card: amount machines of one kind.

var kind: StringName
var amount: int = 1


static func make(p_kind: StringName, p_amount: int) -> RewardOffer:
	var o: RewardOffer = RewardOffer.new()
	o.kind = p_kind
	o.amount = p_amount
	return o


## "Fire ×2".
func label() -> String:
	return "%s ×%d" % [MachineCatalog.get_def(kind).display_name, amount]
