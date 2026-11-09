# v3 font sources (subsets)

| File | Font | Licence | Notes |
| --- | --- | --- | --- |
| InterSB-tnum.otf | Inter SemiBold | SIL OFL 1.1 (OFL-Inter.txt) | Tabular figures frozen on (pyftfeatfreeze -f tnum); Latin subset |
| InterM-tnum.otf | Inter Medium | SIL OFL 1.1 (OFL-Inter.txt) | Same treatment |
| NotoAr600.ttf | Noto Sans Arabic SemiBold | SIL OFL 1.1 (OFL-NotoSansArabic.txt) | Arabic letters, harakat, Arabic digits, Presentation Forms-B |
| NotoAr400.ttf | Noto Sans Arabic Regular | SIL OFL 1.1 (OFL-NotoSansArabic.txt) | Same subset |

`../gen_fonts.sh` converts these into the LVGL fonts in `src/ui/v3/fonts/` (committed; a normal build does not need node).
