class_name PayTable
extends Resource

## Emitted whenever the rules array is modified via add_rule() or direct assignment.
signal rules_changed


class PayLineRule:
	var symbols: Array[String] = []
	var payout_multiplier: int = 0
	var label: String = ""

	func _init(p_label: String, p_symbols: Array[String], p_multiplier: int) -> void:
		label = p_label
		symbols = p_symbols
		payout_multiplier = p_multiplier


## Ordered list of payout rules. Higher-value rules should appear first so
## evaluate() and get_matching_rule() short-circuit on the best match.
@export var rules: Array[PayLineRule] = []

## Symbol ID that substitutes for any other symbol during matching.
## Leave empty to disable wild substitution entirely.
@export var wild_symbol: String = ""


## Returns ",".join(symbols) — used as the canonical dictionary key throughout
## the slot machine, keeping key format consistent in one place.
static func combo_key(symbols: Array[String]) -> String:
	return ",".join(symbols)


## Returns true if candidate matches target, accounting for wild substitution.
## A wild in the incoming combo matches any target symbol; a wild in the rule
## itself is not handled here — rule symbols are expected to be explicit.
func _symbol_matches(candidate: String, target: String) -> bool:
	if candidate == target:
		return true
	# Wild substitution: the combo symbol is a wild and the rule expects something concrete.
	if wild_symbol != "" and candidate == wild_symbol:
		return true
	return false


## Returns the first PayLineRule whose symbols match combo (respecting wilds),
## or null if no rule matches. Rules are checked in declaration order, so place
## higher-value rules first in the @export var rules array.
func get_matching_rule(combo: Array[String]) -> PayLineRule:
	for rule: PayLineRule in rules:
		if rule.symbols.size() != combo.size():
			continue
		var matched: bool = true
		for i: int in range(combo.size()):
			if not _symbol_matches(combo[i], rule.symbols[i]):
				matched = false
				break
		if matched:
			return rule
	return null


## Returns bet * rule.payout_multiplier for the first matching rule, or 0.
func evaluate(combo: Array[String], bet: int) -> int:
	var rule: PayLineRule = get_matching_rule(combo)
	if rule == null:
		return 0
	return bet * rule.payout_multiplier


## Builds the flat "sym,sym,sym" -> multiplier Dictionary that SlotMachine
## expects in its @export var paytable field. Wild substitution is not expanded
## here — only the exact rule symbol sequences are emitted as keys. If two
## rules would produce the same key, the first one (higher priority) wins.
func build_paytable_dict() -> Dictionary:
	var dict: Dictionary = {}
	for rule: PayLineRule in rules:
		var key: String = combo_key(rule.symbols)
		# First rule wins — preserves the "higher-value rules first" contract.
		if not dict.has(key):
			dict[key] = rule.payout_multiplier
	return dict


## Appends a new PayLineRule and notifies listeners. Insert higher-value rules
## before lower-value ones, or sort the array afterward, since evaluate() stops
## at the first match.
func add_rule(label: String, symbols: Array[String], multiplier: int) -> void:
	var rule: PayLineRule = PayLineRule.new(label, symbols, multiplier)
	rules.append(rule)
	rules_changed.emit()
