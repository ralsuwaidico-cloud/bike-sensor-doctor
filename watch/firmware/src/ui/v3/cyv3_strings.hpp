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
    };
    static_assert(sizeof(T) / sizeof(T[0]) == static_cast<size_t>(S::COUNT), "one entry per string id");
    return T[static_cast<int>(id)];
}

inline const char* tr(S id, Lang l) { return l == Lang::Ar ? pair(id).ar : pair(id).en; }

/// printf-style formatting of a translated template (templates carry at most two %d or one %s).
inline std::string trf(S id, Lang l, int a = 0, int b = 0) { char buf[96]; std::snprintf(buf, sizeof buf, tr(id, l), a, b); return buf; }
inline std::string trs(S id, Lang l, const char* s) { char buf[96]; std::snprintf(buf, sizeof buf, tr(id, l), s); return buf; }

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
