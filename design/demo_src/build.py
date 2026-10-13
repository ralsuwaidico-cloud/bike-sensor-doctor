
import re
head=open('design/demo_src/head_part.html').read()
body=open('design/demo_src/body_part.html').read()
eng=open('design/demo_src/engine_part.js').read()
eng=eng.replace('let ride="r1", speedX=10','let ride="r3", speedX=10')
eng=eng.replace("if(!(this.keepArmed || now-this.lastEmit>=c.keepRepeat)) return null;","if(!(this.keepArmed || (c.keepRepeat>0 && now-this.lastEmit>=c.keepRepeat))) return null;")
eng=eng.replace("Zone 2 target (138–149)","Zone 2 target (${CFG.hrTarget[0]}–${CFG.hrTarget[1]})").replace("coach's Zone 2 (138–149)","coach's Zone 2 (${CFG.hrTarget[0]}–${CFG.hrTarget[1]})").replace("Zone 2 target; ${pct(2)+pct(3)+pct(4)}%","Zone 2 target (${CFG.hrTarget[0]}–${CFG.hrTarget[1]}); ${pct(2)+pct(3)+pct(4)}%")
app=open('design/demo_src/app_part.js').read()
css=open('design/demo_src/css_add.txt').read()
head=head.replace('</style>',css,1) if '/* ---- app frame' not in head else head
open('/home/claude/bike-sensor-doctor/design/coach_demo.html','w').write(head+body+"\n<script>\n"+eng+"\n"+app+"\n</script>\n")
print("built")
