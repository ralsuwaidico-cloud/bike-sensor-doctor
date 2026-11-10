#pragma once
// Cyclift Watch v3 — interface strings for the Stage 1 screens (Orbit face, app menu, cycling cockpit), English and Arabic.
// Wording follows the approved prototype (Deliverable D v3.1). Technical abbreviations stay Latin in both languages:
// W, bpm, rpm, km, kg, FTP, HRV. English strings for label and chip styles are stored in their displayed (upper) case.
#include <cstdint>
#include <cstdio>
#include <string>

namespace cyw::v3 {

enum class Lang : uint8_t { En, Ar };

enum class S : uint16_t {
    // status words and chips
    PhoneLost, NotSynced, Paused, WaitingHr, EaseOff,
    // face
    NextRide, Move, Load,
    // menu
    ReturnToWorkout, WatchFace, Today, Activities, Health, Coach, History, Utilities, Settings, More,
    // cockpit
    Interval, HeartRate, Cadence, Hold, PushTo, HrBand,
    Pause, Pausing, Resume, Resuming,
    // command results
    ToastPaused, ToastResumed, ToastLapSaved, PhoneLostUseIphone,
    UnablePause, UnableResume, UnableLap, NoAnswer, WorkoutChanged,
    KeyLapPressAgain,
    // Stage 1.3: face neighbourhood (Today, Week, Quick Settings, widgets), not-yet pages, Bike mode, simulated ride
    QuickSettings, Brightness, Theme, Dnd, Mode, ScreenLock, On, Off, Wrist, Bike, Gym,
    ThObsidian, ThArctic, ThOcean, ThForest, ThSandstone, ThContrast, LockedHoldKey1,
    TodayHdr, WeekHdr, WeekLink, Target, Start, PlanName, PlanSub, NoPlanTitle, NoPlanSub, PlanOneOnIphone,
    SessionsDone, MissedWed, IphoneAdjusts,
    HealthHdr, CoachHdr, RestingHr, Hrv, NoNote, CoachNote, Why, StepsLbl, OfGoal, Estimated, MinKcal,
    NotInRelease, ArrivesLater, SimRide, SimRideSub, Watts,
    COUNT
};

struct Pair { const char* en; const char* ar; };

inline const Pair& pair(S id) {
    static const Pair T[] = {
        {"PHONE LOST", "فُقد الهاتف"},
        {"NOT SYNCED", "غير متزامن"},
        {"PAUSED", "متوقف"},
        {"WAITING HR", "بانتظار النبض"},
        {"EASE OFF", "خفّف الجهد"},
        {"Next \xC2\xB7 Ride %s", "التالي \xC2\xB7 ركوب %s"},
        {"Move", "الحركة"},
        {"Load", "الحمل"},
        {"Return to workout", "العودة إلى التمرين"},
        {"Watch Face", "واجهة الساعة"},
        {"Today", "اليوم"},
        {"Activities", "الأنشطة"},
        {"Health", "الصحة"},
        {"Coach", "المدرب"},
        {"History", "السجل"},
        {"Utilities", "الأدوات"},
        {"Settings", "الإعدادات"},
        {"%d more", "%d أخرى"},
        {"INTERVAL", "فترة"},
        {"Heart rate", "نبض القلب"},
        {"Cadence", "الإيقاع"},
        {"HOLD %d W", "ثبّت %d W"},
        {"PUSH TO %d W", "ارفع إلى %d W"},
        {"HR %d\xE2\x80\x93%d", "النبض %d\xE2\x80\x93%d"},
        {"Pause", "إيقاف مؤقت"},
        {"Pausing\xE2\x80\xA6", "جارٍ الإيقاف\xE2\x80\xA6"},
        {"Resume", "استئناف"},
        {"Resuming\xE2\x80\xA6", "جارٍ الاستئناف\xE2\x80\xA6"},
        {"Paused", "متوقف مؤقتًا"},
        {"Resumed", "تم الاستئناف"},
        {"Lap saved", "تم حفظ اللفة"},
        {"Phone lost \xE2\x80\x94 use iPhone", "الهاتف مفقود \xC2\xB7 استخدم iPhone"},
        {"Unable to pause", "تعذّر الإيقاف"},
        {"Unable to resume", "تعذّر الاستئناف"},
        {"Unable to save lap", "تعذّر حفظ اللفة"},
        {"No answer from iPhone", "لا رد من iPhone"},
        {"Workout changed on iPhone", "تغيّر التمرين على iPhone"},
        {"LAP \xC2\xB7 PRESS AGAIN", "لفة \xC2\xB7 اضغط مجددًا"},
        {"QUICK SETTINGS", "الإعدادات السريعة"},
        {"Brightness", "السطوع"},
        {"Theme", "السمة"},
        {"Do not disturb", "عدم الإزعاج"},
        {"Mode", "الوضع"},
        {"Screen lock", "قفل الشاشة"},
        {"On", "تشغيل"},
        {"Off", "إيقاف"},
        {"Wrist", "المعصم"},
        {"Bike", "الدراجة"},
        {"Gym", "الصالة"},
        {"Obsidian", "أوبسيديان"},
        {"Arctic", "القطب"},
        {"Ocean", "المحيط"},
        {"Forest", "الغابة"},
        {"Sandstone", "الحجر الرملي"},
        {"High contrast", "تباين عالٍ"},
        {"LOCKED \xC2\xB7 HOLD KEY 1", "مقفل \xC2\xB7 اضغط المفتاح ١ مطولًا"},
        {"TODAY", "اليوم"},
        {"WEEK", "الأسبوع"},
        {"Week", "الأسبوع"},
        {"TARGET", "الهدف"},
        {"Start", "ابدأ"},
        {"Sweet-spot intervals", "فترات التحمل"},
        {"%d min \xC2\xB7 %s min", "%d د \xC2\xB7 %s د"},
        {"No plan on the watch yet", "لا توجد خطة على الساعة بعد"},
        {"Today\xE2\x80\x99s plan comes from iPhone", "تأتي خطة اليوم من iPhone"},
        {"Plan one on iPhone", "خطط لتمرين على iPhone"},
        {"%d of %d sessions done", "%d من %d جلسات منجزة"},
        {"1 missed \xC2\xB7 Wed", "جلسة فائتة واحدة \xC2\xB7 الأربعاء"},
        {"iPhone adjusts the plan", "يعدّلها iPhone تلقائيًا"},
        {"HEALTH", "الصحة"},
        {"COACH", "المدرب"},
        {"Resting HR", "نبض الراحة"},
        {"HRV", "تقلب النبض"},
        {"No note yet. Plan your week on iPhone.", "لا توجد ملاحظة بعد. خطط لأسبوعك على iPhone."},
        {"Your legs recovered well from Thursday. Today: sweet-spot, 60 min.", "تعافت ساقاك جيدًا من تمرين الخميس. اليوم: فترات 60 دقيقة."},
        {"Why?", "لماذا؟"},
        {"STEPS", "الخطوات"},
        {"of %s", "من %s"},
        {"Estimated", "تقديري"},
        {"%s min \xC2\xB7 %s kcal", "%s د \xC2\xB7 %s سعرة"},
        {"Not in this release", "غير متاح في هذا الإصدار"},
        {"Arrives in a later update", "يصل في تحديث لاحق"},
        {"Simulated ride", "ركوب محاكى"},
        {"No sensors \xC2\xB7 demo values", "لا مستشعرات \xC2\xB7 قيم تجريبية"},
        {"WATTS", "واط"},
    };
    static_assert(sizeof(T) / sizeof(T[0]) == static_cast<size_t>(S::COUNT), "one entry per string id");
    return T[static_cast<int>(id)];
}

inline const char* tr(S id, Lang l) { return l == Lang::Ar ? pair(id).ar : pair(id).en; }

/// printf-style formatting of a translated template (templates carry at most two %d or one %s).
inline std::string trf(S id, Lang l, int a = 0, int b = 0) { char buf[96]; std::snprintf(buf, sizeof buf, tr(id, l), a, b); return buf; }
inline std::string trs(S id, Lang l, const char* s) { char buf[96]; std::snprintf(buf, sizeof buf, tr(id, l), s); return buf; }
inline std::string trds(S id, Lang l, int a, const char* s) { char buf[96]; std::snprintf(buf, sizeof buf, tr(id, l), a, s); return buf; }
inline std::string trss(S id, Lang l, const char* a, const char* b) { char buf[96]; std::snprintf(buf, sizeof buf, tr(id, l), a, b); return buf; }

inline const char* weekday(int wd, Lang l) {          // 0 = Sunday
    static const char* en[] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"};
    static const char* ar[] = {"الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"};
    return (l == Lang::Ar ? ar : en)[((wd % 7) + 7) % 7];
}
inline const char* month(int m, Lang l) {             // 1..12
    static const char* en[] = {"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"};
    static const char* ar[] = {"يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"};
    return (l == Lang::Ar ? ar : en)[(m - 1 + 12) % 12];
}

} // namespace cyw::v3
