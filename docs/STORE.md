# صقر — SAQR · تجهيز متجر Meta Horizon

هذا الملف لصاحب اللعبة. **Claude لا يرفع شيئًا للمتجر**؛ الرفع يتم من حساب المطوّر بيد صاحب اللعبة.

## ما تم داخل اللعبة (v1.0)
- إيقاف مؤقت تلقائي عند فتح قائمة Meta أو فقد التركيز، وزر القائمة الأيسر ☰ يوقف ويكمل.
- معدل تحديث 90Hz افتراضيًا على Quest 3/3S (72/90/120 من الإعدادات)، تنعيم MSAA 4×، Foveation ديناميكي.
- لا إنترنت، لا ميكروفون، لا كاميرا، لا جمع بيانات. الحفظ محلي فقط (`saqr_profile.json`).
- لا صلاحية مشهد/غرفة في هذه النسخة (مسح الغرفة متوقف).
- عربي وإنجليزي.
- شعار عبودين قيمز يظهر مرة واحدة كشاشة Meta الافتتاحية.

## المتبقي عليك قبل الإرسال
1. **مفتاح توقيع للمتجر** (مرة واحدة، واحفظه للأبد — بدونه ما تقدر تحدّث اللعبة بعدين). Claude يجهزه لك عند الطلب، وأنت تضيفه في أسرار المستودع:
   `SAQR_KEYSTORE_B64` و `SAQR_KEYSTORE_PASS`. بعدها البناء يطلع `SAQR-Quest-v1.0.0-store.apk` في artifacts.
2. تجربة كاملة على النظارة 15 دقيقة على الأقل (بدون تعليق أو هبوط أداء).
3. لقطات من داخل النظارة نفسها (3 على الأقل، 2560×1440) — صور المعاينة المكتبية ما تنفع للمتجر.
4. صورة رئيسية 2560×1440 (النص داخل 80% من المنتصف) وأيقونة 1024×1024.
5. رابط سياسة خصوصية (موقع عبودين قيمز) — اللعبة لا تجمع بيانات.
6. تقييم الراحة: **متوسط (Moderate)** — اللاعب واقف والطيارة تتحرك حوله، لا حركة للكاميرا.
7. استبيان IARC: عنف كرتوني خفيف (طائرات ودبابات كرتونية تنفجر، لا دم، لا بشر يتأذون — الطيار ينزل بالمظلة).

## نص المتجر المقترح
**الاسم:** صقر — SAQR

**وصف قصير (عربي):** طيّر طيارة حربية كرتونية حقيقية في غرفتك! ثماني مهمات، دفاع جوي، قاذفة عملاقة، وحظيرة لتطوير طيارتك.

**Short description (English):** Fly a cartoon warplane for real in your own room — eight missions, ground anti-air, a giant bomber and a hangar full of upgrades.

**الوصف الطويل (عربي):**
طيارتك واقفة على أرض غرفتك. افتح البنزين، اجرِ على الأرض، وأقلع — كل شيء بيدك مثل الطيارات اللاسلكية.
- 8 مهمات: مدرسة الطيران، دورية الفجر، القافلة، المرافقة، سماء مشتعلة، غارة على القاعدة، الدفاع عن المطار، والعملاق عند الغروب.
- جنود على الأرض يجهزون الدفاع الجوي ثانيتين ثم يطلقون — اهرب، لف، أو أسقط الصاروخ.
- الحظيرة: محرك، درع، رشاشات، صواريخ، رباعي حارق، مدفع 20 ملم، قنابل عنقودية، ألغام جوية، الصاعقة، ومشاعل التمويه.
- إذا انضربت طيارتك تتفكك قطعًا وينزل الطيار بالمظلة.
- ثلاث درجات صعوبة، عربي وإنجليزي.

**Long description (English):**
Your plane is parked on your floor. Open the throttle, roll, and take off — fully hand-flown like a radio-controlled model.
- 8 missions: Flight School, Dawn Patrol, The Convoy, Escort, Burning Skies, Base Raid, Hold the Airfield and The Giant at dusk.
- Ground crews set up anti-air for two seconds, then fire — outturn it, barrel-roll or shoot it down.
- Hangar: engine, armor, guns, rockets, incendiary quad guns, 20 mm cannon, cluster bombs, air mines, the Thunderbolt and flares.
- Get shot down and your plane breaks apart while the pilot parachutes to safety.
- Three difficulty levels, Arabic and English.

**التصنيف:** Games · Action / Flying · Mixed Reality
