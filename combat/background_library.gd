class_name BackgroundLibrary
extends RefCounted

## Code registry of placeholder Backgrounds (spec 2026-08-13-character-creation-design.md). Mirrors
## ClassLibrary: returns a FRESH Background each call. Only 2 entries exist -- enough to prove the
## creation-screen pipeline, not a full roster (deferred to a later design-bible content session).

const IDS: Array[StringName] = [&"reformed_vermin", &"abbey_cook"]

static func make(id: StringName) -> Background:
	match id:
		&"reformed_vermin":
			var b: Background = Background.new()
			b.background_name = "Reformed Vermin"
			b.flavor_text = "Once one of the Wildcat's own -- now fighting for the other side."
			var face: ReelFace = ReelFace.new()
			face.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			face.multiplier = 1.5
			b.signature_face = face
			return b
		&"abbey_cook":
			var b: Background = Background.new()
			b.background_name = "Abbey-Cook"
			b.flavor_text = "Years at the hearth taught patience, and a knack for a well-timed breather."
			var face: ReelFace = ReelFace.new()
			face.result_tier = ReelFace.ResultTier.NEUTRAL
			face.multiplier = 1.0
			b.signature_face = face
			return b
		_:
			return null
