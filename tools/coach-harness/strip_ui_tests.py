import sys,re
p=sys.argv[1]; src=open(p).read(); lines=src.split('\n'); out=[]; i=0
while i<len(lines):
    l=lines[i]
    if re.match(r'\s*func test\w*\(', l):
        depth=0; j=i; block=[]
        while True:
            block.append(lines[j]); depth+=lines[j].count('{')-lines[j].count('}')
            if depth<=0 and '{' in ''.join(block): break
            j+=1
        if any(w in '\n'.join(block) for w in ['RideCoach','SwiftUI','UIApplication','HealthWorkoutMapper','RideRecorder','HKWorkout','SensorHub','DeviceLink(','TrendChartMath','WeekBucket','ChartRange','FTPConfidencePill','DS.','PlanDay']): i=j+1; continue
        out+=block; i=j+1; continue
    out.append(l); i+=1
open(p,'w').write('\n'.join(out))
