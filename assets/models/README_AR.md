# أصول SHADDA — الجرد

`original/` يحفظ الأصول المعتمدة **دون أي تعديل** (مصادر Blender وملفات GLB عالية الجودة LOD0). `runtime/` يحوي النسخ المستخدمة فعليًا داخل اللعبة: LOD2 من الحزم نفسها، منسوخة بايتًا ببايت دون إعادة تصدير. البصمات في `MANIFEST.sha256` وتُفحص بـ `sha256sum -c` من داخل هذا المجلد.

ملفات `original/` مستثناة من استيراد Godot (`.gdignore`) ومن حزمة APK (`exclude_filter`)، فلا تدخل ملفات Blender ولا الخامات الثقيلة إلى الجهاز.

## original/ (20 ملفًا)

| الأصل | GLB (LOD0) | Blender | مثلثات LOD0 | المصدر في الحزمة |
|---|---|---|---|---|
| الروبوت A — الحارس | shadda_robot_A.glb | shadda_robot_A.blend | 158,370 | SHADDA_Robots_and_Power_3D |
| الروبوت B — النشّال | shadda_robot_B.glb | shadda_robot_B.blend | 88,644 | SHADDA_Robots_and_Power_3D |
| الروبوت C — الثقيل | shadda_robot_C.glb | shadda_robot_C.blend | 81,111 | SHADDA_Robots_and_Power_3D |
| الروبوت D — المتسلق | shadda_robot_D.glb | shadda_robot_D.blend | 111,084 | SHADDA_Robots_and_Power_3D |
| محطة البطاريات | shadda_battery_station.glb | shadda_battery_station.blend | 40,195 | SHADDA_Robots_and_Power_3D |
| البطارية | shadda_power_cell.glb | shadda_power_cell.blend | 26,420 | SHADDA_Robots_and_Power_3D |
| القفاز الأيسر | shadda_gauntlet_left.glb | shadda_gauntlet_left.blend | 37,328 | SHADDA_Gauntlets_and_Rift_3D |
| القفاز الأيمن | shadda_gauntlet_right.glb | shadda_gauntlet_right.blend | 37,422 | SHADDA_Gauntlets_and_Rift_3D |
| الفجوة (متوسطة + المجموعات الثلاث في Blender) | shadda_portal.glb | shadda_portal.blend | 12,234 | SHADDA_Gauntlets_and_Rift_3D |
| الفجوة الصغيرة | shadda_portal_small.glb | — | 10,286 | SHADDA_Gauntlets_and_Rift_3D |
| الفجوة الكبيرة | shadda_portal_large.glb | — | 14,128 | SHADDA_Gauntlets_and_Rift_3D |

ستة ملفات Blender كانت مرفوعة كـ Git blobs غير مرتبطة بأي commit (الروبوتات A/B/C، المحطة، البطارية، القفاز الأيمن)؛ تحقّقنا أن بصمات Git الخاصة بها تطابق ملفات الحزمة بايتًا ببايت، ورُبطت في الشجرة عبر Git Data API دون إعادة رفع. الملفات الثلاثة الباقية (القفاز الأيمن GLB، الفجوة GLB وBlend) رُفعت كـ blobs جديدة بترميز base64 القياسي للـAPI، وهو ما يحفظ البايتات الأصلية تمامًا؛ لم يُعدَّل أي أصل لتجاوز حدود الأدوات.

## runtime/ (9 ملفات، LOD2)

| الملف | المثلثات | المواد | ملاحظة |
|---|---:|---:|---|
| shadda_robot_A.glb | 42,084 | 10 | lod/shadda_robot_A_LOD2.glb |
| shadda_robot_B.glb | 29,884 | 8 | lod/shadda_robot_B_LOD2.glb |
| shadda_robot_C.glb | 24,327 | 10 | lod/shadda_robot_C_LOD2.glb |
| shadda_robot_D.glb | 34,878 | 9 | lod/shadda_robot_D_LOD2.glb |
| shadda_battery_station.glb | 11,927 | 13 | lod/shadda_battery_station_LOD2.glb |
| shadda_power_cell.glb | 7,800 | 10 | lod/shadda_power_cell_LOD2.glb |
| shadda_rift_small.glb | 5,670 | 10 | lod/shadda_portal_small_LOD2.glb — تُخفى خامة الجدار البديل M_Rift_Wall_Replaceable لأن Passthrough يُظهر الغرفة الحقيقية |
| shadda_gauntlet_left.glb | 14,254 | 9 | lod/shadda_gauntlet_left_LOD2.glb |
| shadda_gauntlet_right.glb | 14,348 | 9 | lod/shadda_gauntlet_right_LOD2.glb |

أسوأ حالة على الشاشة (3 روبوتات من فئة A + المحطة + 3 بطاريات + 3 فجوات + القفازان) ≈ 233 ألف مثلث و≈ 480 سطح رسم قبل التجميع. هذا رقم من الملفات، وليس قياس أداء على Quest 3.

## إعادة التلوين النيون

لا يُعدَّل أي ملف GLB. `systems/neon.gd` يستبدل عند التشغيل مواد المضيئات فقط (M_Amber_Emitter, M_Cyan_Emitter, M_Cyan_Diagnostics, M_DisplayCount_*, M_DisplaySlot_01, M_Rift_*) بمواد غير مظللة بألوان نيون متحركة، ويضيف هالات Premultiplied-alpha وحلقات أرضية. خامات PBR الأخرى (الطلاء، المعدن، المطاط) تبقى كما صُدّرت.

## ما لم يُنجز بعد

- شرط 3 مواد كحد أقصى للقفاز (حاليًا 9) وميزانية 20 ألف مثلث للروبوتات لم يتحققا؛ يحتاجان إعادة خبز/دمج في Blender، وهو خارج نطاق هذه المرحلة.
- محاذاة القفازات مع وحدات التحكم لم تُختبر على النظارة.
- لم يُقس الأداء على Quest 3.
