class_name Missions
extends RefCounted
## The campaign: eight missions over the open floor. Each has three stars —
## ★ complete it, ★★ and ★★★ the two goals shown on the briefing.

const LIST := [
	{"id": "training", "icon": "rings", "time": true,
		"title": {"ar": "مدرسة الطيران", "en": "Flight School"},
		"brief": {"ar": "أقلع من أرض غرفتك، اعبر الحلقات الثماني بالترتيب، ثم فجّر بالونات التدريب بالرشاش.", "en": "Take off from your floor, fly the eight rings in order, then pop the training balloons with your guns."},
		"s2": {"ar": "أنهِ خلال 1:40", "en": "Finish within 1:40"}, "s3": {"ar": "أنهِ خلال 1:10", "en": "Finish within 1:10"}},
	{"id": "patrol", "icon": "plane",
		"title": {"ar": "دورية الفجر", "en": "Dawn Patrol"},
		"brief": {"ar": "مقاتلات استطلاع عبرت الحدود وتحتمي خلف بالونات حاجزة. طاردها وأسقطها.", "en": "Scout fighters slipped across the border behind a balloon barrage. Hunt them down."},
		"s2": {"ar": "حافظ على 60% من هيكلك", "en": "Keep 60% of your hull"}, "s3": {"ar": "أسقطها كلها خلال 1:30", "en": "Down them all within 1:30"}},
	{"id": "convoy", "icon": "truck",
		"title": {"ar": "القافلة", "en": "The Convoy"},
		"brief": {"ar": "قافلة إمداد تعبر الأرض تحتك. دمّر 3 مركبات على الأقل قبل ما تهرب — وانتبه لفرق الدفاع الجوي: تتجهز ثانيتين ثم تطلق.", "en": "A supply convoy is crossing the floor. Destroy at least 3 vehicles before they escape — and watch the anti-air teams: two seconds to set up, then they fire."},
		"s2": {"ar": "دمّر 4 من 5", "en": "Destroy 4 of 5"}, "s3": {"ar": "دمّر القافلة كلها", "en": "Destroy the whole convoy"}},
	{"id": "escort", "icon": "shield",
		"title": {"ar": "المرافقة", "en": "Escort"},
		"brief": {"ar": "طائرة الإمداد الصديقة تعبر سماء غرفتك والمقاتلات تلاحقها. احمها حتى تخرج سالمة.", "en": "A friendly supply plane is crossing your room with fighters on its tail. Keep it alive until it gets away."},
		"s2": {"ar": "الإمداد فوق 50%", "en": "Supply plane above 50%"}, "s3": {"ar": "الإمداد فوق 85%", "en": "Supply plane above 85%"}},
	{"id": "dogfight", "icon": "guns",
		"title": {"ar": "سماء مشتعلة", "en": "Burning Skies"},
		"brief": {"ar": "ثلاث موجات مقاتلات تناور وتهرب منك. الموجة الأخيرة يقودها البارون الأحمر — طيار نخبة أسرع وأذكى.", "en": "Three waves of fighters that dodge and run. The last is led by the Red Baron — a faster, smarter ace."},
		"s2": {"ar": "حافظ على 60% من هيكلك", "en": "Keep 60% of your hull"}, "s3": {"ar": "حافظ على 85% من هيكلك", "en": "Keep 85% of your hull"}},
	{"id": "base", "icon": "radar", "time": true,
		"title": {"ar": "غارة على القاعدة", "en": "Base Raid"},
		"brief": {"ar": "دمّر الرادار وخزانات الوقود والمدفعين. الخزانات تنفجر انفجارًا متسلسلًا — استغلها.", "en": "Destroy the radar, the fuel tanks and both flak guns. Fuel tanks chain-react — use it."},
		"s2": {"ar": "أنهِ خلال 2:00", "en": "Finish within 2:00"}, "s3": {"ar": "أنهِ خلال 1:20", "en": "Finish within 1:20"}},
	{"id": "airfield", "icon": "home",
		"title": {"ar": "الدفاع عن المطار", "en": "Hold the Airfield"},
		"brief": {"ar": "قاذفات انقضاضية تستهدف حظائر مطارك على الأرض. أسقطها قبل ما تنقض — وانتبه لصفير الانقضاض.", "en": "Dive bombers are going for your hangars on the floor. Shoot them down before they dive — listen for the dive whistle."},
		"s2": {"ar": "احمِ حظيرتين على الأقل", "en": "Save at least 2 hangars"}, "s3": {"ar": "احمِ الحظائر الثلاث", "en": "Save all 3 hangars"}},
	{"id": "giant", "icon": "bomber", "time": true, "dusk": true,
		"title": {"ar": "العملاق", "en": "The Giant"},
		"brief": {"ar": "عند الغروب: القاذفة العملاقة بأربع محركات تدور فوقك ومعها مرافقون. دمّر ثلاثة من محركاتها.", "en": "At dusk: the four-engine giant circles overhead with escorts. Knock out three of its engines."},
		"s2": {"ar": "حافظ على 60% من هيكلك", "en": "Keep 60% of your hull"}, "s3": {"ar": "أنهِ خلال 2:00", "en": "Finish within 2:00"}},
]


static func ids() -> Array:
	return LIST.map(func(m): return m.id)


static func index_of(id: String) -> int:
	for i in range(LIST.size()):
		if LIST[i].id == id:
			return i
	return -1


static func get_m(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]


static func text(m: Dictionary, key: String) -> String:
	var d = m.get(key, {})
	return d.get(Lang.code(), d.get("ar", "")) if d is Dictionary else str(d)
