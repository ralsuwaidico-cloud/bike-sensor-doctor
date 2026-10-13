/* ============================================================ RIDER PROFILE & ONBOARDING (prototype of the app flow) */
const STORE_KEY="bc_rider_profile_v1";
let P={answers:{},completed:false,feedback:[],stepIndex:0};
function loadP(){ try{ const s=localStorage.getItem(STORE_KEY); if(s){ const o=JSON.parse(s); if(o&&o.answers) P=Object.assign(P,o); } }catch(_){} }
function saveP(){ try{ localStorage.setItem(STORE_KEY,JSON.stringify(P)); }catch(_){} }
const A=()=>P.answers;
const DAYS=["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
const GOALS=[["endurance","Improve aerobic endurance and Zone 2 fitness"],["fasterHr","Ride faster at the same heart rate"],["ftp","Increase FTP and sustained power"],["climb","Improve climbing"],["longer","Ride longer without getting exhausted"],["event","Prepare for a race or event"],["fitness","Improve general fitness"],["weight","Lose weight or improve body composition"],["other","Another personal goal"]];
const goalName=k=>(GOALS.find(g=>g[0]===k)||[k,k])[1];

/* Each step: id, question, type, options, why (shown small), when(answers) → relevant?, skip label.
   type: choice | multi | number | two | metric | summary. Metric = value + how it was obtained. */
const STEPS=[
 {id:"age",q:"How old are you?",why:"Age sets a provisional max-HR formula when nothing is measured, and lengthens the warm-up over 50.",type:"number",min:14,max:90,unit:"years",skip:"Skip"},
 {id:"body",q:"Height and weight",why:"Optional. Weight matters for power-to-weight and climbing; nothing else uses it.",type:"two",fields:[["heightCm","Height (cm)",120,220],["weightKg","Weight (kg)",35,160]],skip:"Skip"},
 {id:"experience",q:"How much cycling experience do you have?",why:"New or returning riders get longer warm-ups and slower progression.",type:"choice",options:[["new","New — under a year of regular riding"],["recreational","Recreational — 1 to 3 years"],["experienced","Experienced — 3+ years, some structured training"],["returning","Returning after a long break"]]},
 {id:"env",q:"Where do you usually ride?",why:"Hills and indoor riding change how cadence and power targets are used.",type:"multi",options:[["flat","Flat road"],["hills","Hilly road"],["indoor","Indoor trainer"],["mixed","Mixed / varies"]]},
 {id:"limits",q:"Any exercise limitation the coach should respect?",why:"Only used to keep intensity moderate. You can say no.",type:"choice",options:[["none","No limitations"],["moderate","Yes — keep intensity moderate"],["medical","Yes — I have medical guidance on heart rate"],["private","Prefer not to say"]]},
 {id:"goals",q:"What do you want to achieve? Choose all that apply.",type:"multi",options:GOALS},
 {id:"primary",q:"Which one is your main priority?",why:"The main goal decides the type of session the coach recommends.",type:"choice",options:a=>(a.goals||[]).map(k=>[k,goalName(k)]),when:a=>(a.goals||[]).length>1},
 {id:"success",q:"What would success look like in 3 months?",why:"A measurable target the coach can check against your rides.",type:"choice",options:a=>successOptions(a)},
 {id:"ridesNow",q:"How many times do you cycle per week right now?",type:"choice",options:[["0","0–1"],["2","2"],["3","3"],["4","4"],["5","5 or more"]]},
 {id:"daysAvail",q:"How many days could you realistically train?",why:"The plan never schedules more than this, and adds at most one ride a week over what you do now.",type:"choice",options:[["2","2"],["3","3"],["4","4"],["5","5 or more"]]},
 {id:"typicalMin",q:"Typical ride duration",type:"number",min:20,max:240,step:5,unit:"min",slider:true},
 {id:"longestMin",q:"Longest ride you are comfortable with",type:"number",min:30,max:360,step:10,unit:"min",slider:true},
 {id:"other",q:"Other regular exercise?",why:"The coach plans around it rather than treating cycling as your only training.",type:"multi",options:[["weights","Weight training"],["running","Running"],["swim","Swimming"],["sport","Team or racket sport"],["none","None"]]},
 {id:"otherDays",q:"Which days is that exercise usually on?",why:"Hard rides are not scheduled the day after leg-heavy sessions.",type:"multi",options:DAYS.map(d=>[d,d]),when:a=>(a.other||[]).some(x=>x!=="none"),skip:"Varies"},
 {id:"rest",q:"Preferred rest days?",type:"multi",options:DAYS.map(d=>[d,d]),skip:"No preference"},
 {id:"varies",q:"Does your schedule change from week to week?",type:"choice",options:[["no","Mostly the same"],["yes","Changes often"]]},
 {id:"maxHr",q:"Do you know your maximum heart rate?",why:"Used only if there is no threshold heart rate. A formula is used if unknown, and labelled provisional.",type:"metric",unit:"bpm",min:120,max:220},
 {id:"restHr",q:"Do you know your resting heart rate?",why:"With max HR it gives heart-rate-reserve zones, which fit individuals better than % of max.",type:"metric",unit:"bpm",min:30,max:100},
 {id:"lthr",q:"Do you know your lactate-threshold heart rate?",why:"The best anchor for Zone 2 if it was measured in a test.",type:"metric",unit:"bpm",min:110,max:210},
 {id:"ftp",q:"Do you know your FTP (functional threshold power)?",why:"Without it the coach guides by heart rate only and offers an FTP test later.",type:"metric",unit:"W",min:60,max:450},
 {id:"apple",q:"Import your Apple Fitness heart-rate zones as a provisional reference?",why:"Apple's bands (Z2 = 151–160 bpm) are app-calculated, not your physiology. They are kept only as a labelled reference.",type:"choice",options:[["yes","Yes, keep them as app-calculated reference"],["no","No"]],when:a=>!(a.lthr&&a.lthr.how==="measured")},
 {id:"limiter",q:"What usually limits your rides?",why:"Breathing-limited riders get stricter heart-rate ceilings; leg-limited riders get cadence and strength work.",type:"choice",options:[["breathing","Breathing / heart rate"],["legs","Leg fatigue"],["tired","General tiredness"],["time","Time"],["other","Something else"]]},
 {id:"style",q:"Steady riding or intervals?",type:"choice",options:[["steady","Steady"],["intervals","Intervals"],["mix","A mix"]]},
 {id:"cadence",q:"Do you know your natural cadence?",why:"If known, the cadence range is built around it instead of a generic 80–95.",type:"metric",unit:"rpm",min:50,max:120,hows:[["measured","Measured on a sensor"],["estimated","Rough idea"],["unknown","I don't know"]]},
 {id:"struggleZ2",q:"Do you find it hard to stay in Zone 2 (easy) on rides?",why:"If yes, the ceiling is set a few beats lower and the coach speaks sooner.",type:"choice",options:[["yes","Yes, I drift harder"],["no","No"],["unsure","Not sure"]],when:a=>["endurance","fasterHr","longer","weight","fitness"].includes(primaryGoal(a))},
 {id:"guidance",q:"Prefer heart-rate or power guidance?",type:"choice",options:a=>[["hr","Heart rate"],...((a.ftp&&a.ftp.how!=="unknown")?[["power","Power"],["both","Both"]]:[]),["unsure","Not sure — coach decides"]]},
 {id:"heat",q:"Do you often ride in hot conditions?",why:"Heat raises heart rate for the same effort: longer warm-up, extra drift tolerance, earlier-start advice.",type:"choice",options:[["yes","Yes (Abu Dhabi afternoons)"],["no","No"]]},
 {id:"voice",q:"Spoken coaching or screen only?",type:"choice",options:[["voice","Voice + screen"],["screen","Screen only"]]},
 {id:"freq",q:"How often should the coach speak?",type:"choice",options:[["important","Only important corrections"],["frequent","Frequent guidance"]]},
 {id:"tone",q:"Coaching tone?",type:"choice",options:[["encouraging","Encouraging"],["neutral","Neutral"],["technical","Technical"]]},
 {id:"detail",q:"Simple guidance or detailed explanations?",type:"choice",options:[["simple","Simple"],["detailed","Detailed"]]},
 {id:"cadAdvice",q:"Cadence advice during endurance rides?",type:"choice",options:[["yes","Yes"],["no","No"]]},
 {id:"summary",type:"summary"},
];
function primaryGoal(a){ return a.primary || (a.goals||[])[0] || "endurance"; }
function successOptions(a){ const g=primaryGoal(a); const typ=a.typicalMin||60;
  const m={endurance:[["z2_75","Hold Zone 2 for 75 minutes without drifting up"],["z2_90pct","90% of a ride inside Zone 2"],["drift5","Heart-rate drift under 5% on a steady hour"]],
    fasterHr:[["speed1","+1 km/h at the same average heart rate on my route"],["eff5","5% better speed-per-heartbeat"]],
    ftp:[["ftp5","+5% FTP in a test"],["ftp10","+10% FTP in a test"]],
    climb:[["climb","Same climb at a lower heart rate"],["climb_w","More watts per kilo on climbs"]],
    longer:[["long20",`A ${Math.round((a.longestMin||90)*1.2)}-minute ride feeling fresh at the end`],["long_hr","Finish long rides without the final heart-rate surge"]],
    event:[["event_done","Complete the event comfortably"],["event_time","Beat a target time"]],
    fitness:[["fit3","Three rides a week, every week"],["fit_rest","Lower resting heart rate"]],
    weight:[["w_consist","Consistent weekly riding time"],["w_long","Longer easy rides each week"]],
    other:[["own","I'll describe it later in the profile"]]};
  return (m[g]||m.other).concat([["unsure","Not sure yet — the coach proposes one"]]); }
function visibleSteps(){ return STEPS.filter(s=>!s.when||s.when(A())); }

/* ---------------- derive the coaching configuration from the profile (transparent rules) ---------------- */
function deriveConfig(a){
  const R=[]; const rule=(what,because)=>R.push({what,because});
  const c=Object.assign({},GENERIC,{name:"Your coach",rules:R});
  // --- heart-rate zones ---
  const lthr=a.lthr&&a.lthr.how!=="unknown"?a.lthr.value:null, maxHr=a.maxHr&&a.maxHr.how!=="unknown"?a.maxHr.value:null, rest=a.restHr&&a.restHr.how!=="unknown"?a.restHr.value:null;
  let z2, edges, conf;
  if(lthr){ z2=[Math.round(lthr*0.83),Math.round(lthr*0.90)]; edges=[z2[0],Math.round(lthr*0.90)+1,Math.round(lthr*0.95)+1,lthr+1]; conf=(a.lthr.how==="measured")?"CONFIRMED — threshold HR from a test":"PROVISIONAL — threshold HR "+(a.lthr.how==="app"?"calculated by another app":"estimated from workouts"); rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm (83–90% of threshold ${lthr})`,"You gave a threshold heart rate; threshold-based zones fit individuals better than % of max."); }
  else if(maxHr&&rest){ const hrr=maxHr-rest; z2=[Math.round(rest+0.60*hrr),Math.round(rest+0.70*hrr)]; edges=[z2[0],Math.round(rest+0.70*hrr)+1,Math.round(rest+0.80*hrr)+1,Math.round(rest+0.90*hrr)+1]; conf=(a.maxHr.how==="measured"?"PROVISIONAL — heart-rate reserve from a measured max":"PROVISIONAL — heart-rate reserve from an estimated max"); rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm (60–70% of heart-rate reserve, rest ${rest}, max ${maxHr})`,"Max and resting HR known → Karvonen zones instead of plain % of max."); }
  else if(maxHr){ z2=[Math.round(maxHr*0.60),Math.round(maxHr*0.70)]; edges=[z2[0],Math.round(maxHr*0.70)+1,Math.round(maxHr*0.80)+1,Math.round(maxHr*0.90)+1]; conf="PROVISIONAL — % of "+(a.maxHr.how==="measured"?"measured":"estimated")+" max HR"; rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm (60–70% of max ${maxHr})`,"Only max HR known."); }
  else { const est=a.age?Math.round(208-0.7*a.age):185; z2=[Math.round(est*0.60),Math.round(est*0.70)]; edges=[z2[0],Math.round(est*0.70)+1,Math.round(est*0.80)+1,Math.round(est*0.90)+1]; conf=a.age?`GENERIC — max HR ${est} from the Tanaka age formula; please calibrate`:"GENERIC — max HR 185 assumed; please calibrate"; rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm from ${a.age?"an age formula":"a default max HR"}`,"No heart-rate values known. A calibration ride (20-min test) is recommended before trusting these."); }
  c.hrTarget=z2; c.hrZoneEdges=edges; c.zoneConfidence=conf; c.hrCap=z2[1];
  if(a.struggleZ2==="yes"){ c.hrCap=z2[1]-3; rule(`Ceiling lowered to ${c.hrCap} bpm (3 below the top of Zone 2)`,"You said you drift harder than Zone 2; the coach speaks before you leave it."); }
  if(a.limiter==="breathing"){ c.hrCap=Math.min(c.hrCap,z2[1]-2); rule("Stricter heart-rate ceiling","Breathing/heart rate limits you, so heart rate is the first thing the coach protects."); }
  if(a.limits==="moderate"||a.limits==="medical"){ c.hrCap=Math.min(c.hrCap,z2[1]-5); rule("Intensity kept moderate: ceiling 5 bpm under Zone 2 top, no interval sessions","You asked for moderate intensity."); }
  if(a.apple==="yes") rule("Apple zones kept as a labelled reference (Z2 151–160 bpm), not used for coaching","App-calculated bands are not your physiology.");
  // --- power ---
  const ftp=a.ftp&&a.ftp.how!=="unknown"?a.ftp.value:null;
  if(ftp){ c.ftp=ftp; c.ftpKnown=true; c.powerCoaching=(a.guidance!=="hr"); rule(`Power Zone 2 = ${Math.round(ftp*0.55)}–${Math.round(ftp*0.75)} W (55–75% of FTP ${ftp}, ${a.ftp.how})`,a.ftp.how==="measured"?"FTP from a test → power targets are confirmed.":"FTP not from a test → power targets are provisional until a 20-minute test."); if(!c.powerCoaching) rule("Power shown but not coached","You prefer heart-rate guidance."); }
  else { c.ftp=200; c.ftpKnown=false; c.powerCoaching=false; rule("Power targets OFF — heart-rate guidance only; FTP test offered after 3 rides","FTP unknown. The coach never invents watts targets."); }
  // --- cadence ---
  const nat=a.cadence&&a.cadence.how!=="unknown"?a.cadence.value:null;
  c.cadRange= nat?[Math.max(70,nat-5),Math.min(105,nat+5)]:[80,95]; c.cadenceEnabled=(a.cadAdvice!=="no");
  if(nat) rule(`Cadence range ${c.cadRange[0]}–${c.cadRange[1]} rpm around your natural ${nat}`,"Known cadence → targets built around you, not a generic 80–95.");
  if(a.cadAdvice==="no") rule("Cadence hints off during endurance rides","Your preference."); else if(a.limiter==="legs") rule("Cadence hints prioritised (legs limit you)","Higher cadence shifts load from muscles to the aerobic system.");
  // --- warm-up / cool-down ---
  let wu=5, cd=5; if((a.age||0)>=50){wu+=5; rule("Warm-up 10 min instead of 5","Age 50+: a longer warm-up protects the heart-rate response.");} if(a.experience==="new"||a.experience==="returning"){wu+=3; rule("Warm-up +3 min","New or returning rider.");} if(a.heat==="yes"){wu+=3; cd+=3; rule("Warm-up and cool-down +3 min, heart-rate drift tolerance +3%, earlier-start advice","You ride in heat; heart rate runs higher for the same effort.");}
  c.warmupSec=wu*60; c.cooldownSec=cd*60; c.ramps=true; c.grace=true; c.backoff=true;
  // --- communication ---
  c.voice=(a.voice!=="screen"); c.tone=a.tone||"neutral"; c.detail=a.detail||"detailed";
  if(a.freq==="important"){ c.sameRepeat=90000; c.keepRepeat=0; rule("Coach speaks only on corrections; 'keep it up' is shown, not repeated; same cue at most every 90 s","You asked for important corrections only."); } else { c.sameRepeat=45000; c.keepRepeat=90000; rule("Frequent guidance: cues up to every 45 s, 'keep it up' every 90 s","You asked for frequent guidance."); }
  rule("After 3 unheeded repeats the coach goes quiet until something changes (v0.8 proposal)","Replay of your 5 Oct ride showed ~60 repeats otherwise.");
  if(a.varies==="yes") rule("Plan proposed day by day, not as a fixed week","Your schedule changes.");
  return c;
}

/* ---------------- workout recommendation (transparent rules) ---------------- */
function rideLog(){ return P.feedback||[]; }
function recommend(a,c){
  const g=primaryGoal(a); const typ=a.typicalMin||60, long=a.longestMin||90; const why=[], how=[], measure=[];
  const last=rideLog()[rideLog().length-1];
  const today=DAYS[(new Date().getDay()+6)%7]; const yesterday=DAYS[(new Date().getDay()+5)%7];
  let name="Zone 2 endurance", minutes=Math.min(Math.max(30,typ),long), kind="z2";
  if(["ftp"].includes(g)&&c.ftpKnown&&a.limits!=="moderate"&&a.limits!=="medical"){ name="Sweet-spot intervals (3 × 10 min at 88–93% FTP)"; kind="ss"; minutes=Math.max(60,typ); why.push("Main goal is FTP and your FTP is known, so the session targets sustained power."); }
  else if(g==="ftp"){ why.push("Main goal is FTP, but FTP is unknown: endurance base first, FTP test offered after three rides."); }
  else if(g==="climb"&&(a.experience==="experienced")&&a.limits==="none"){ name="Zone 2 with 4 × 5 min low-cadence (60–70 rpm) strength blocks"; kind="strength"; why.push("Climbing goal and experienced rider: low-cadence strength work inside an endurance ride."); }
  else if(g==="fasterHr"){ name="Zone 2 endurance with cadence focus"; why.push("Riding faster at the same heart rate comes from aerobic base plus efficient cadence."); }
  else if(g==="event"&&a.style!=="steady"){ name="Zone 2 endurance (event build, week 1)"; why.push("Event goal: base first, intensity added from week 3."); }
  else why.push(`Main goal is ${goalName(g).toLowerCase()}: Zone 2 endurance is the session that builds it.`);
  // schedule / recovery
  if((a.other||[]).includes("weights")&&(a.otherDays||[]).includes(yesterday)){ if(kind!=="z2"){ name="Zone 2 endurance (easy day after weights)"; kind="z2"; } minutes=Math.min(minutes,typ); why.push(`You lifted weights yesterday (${yesterday}); the coach keeps today easy.`); }
  if((a.rest||[]).includes(today)) why.push(`${today} is one of your rest days — this is for your next riding day.`);
  // feedback adaptation
  if(last){ if(last.rpe>=8||last.recovered==="no"){ name="Recovery spin (Zone 1)"; kind="rec"; minutes=Math.min(40,typ); why.push(`Your last ride felt ${last.rpe}/10${last.recovered==="no"?" and you are not recovered":""}: an easy spin keeps the habit without adding load.`); }
    else if(last.rpe<=4&&last.inZonePct>=80){ minutes=Math.min(Math.round(minutes*1.1/5)*5,long); why.push(`Last ride felt easy (${last.rpe}/10) with ${last.inZonePct}% in zone → duration +10%.`); }
    else if(last.inZonePct<60){ why.push(`Only ${last.inZonePct}% of your last ride was inside the zone → same duration again, stricter ceiling, until the zone is held.`); }
    if(last.limiter==="legs") why.push("Legs limited you last time → cadence hints prioritised today."); }
  const wu=c.warmupSec/60, cd=c.cooldownSec/60;
  const hrT=kind==="rec"?[c.hrTarget[0]-15,c.hrTarget[0]-1]:[c.hrTarget[0],c.hrCap];
  const pwT=c.powerCoaching?(kind==="ss"?[Math.round(c.ftp*0.88),Math.round(c.ftp*0.93)]:[Math.round(c.ftp*0.55),Math.round(c.ftp*0.75)]):null;
  how.push(`${wu}-min warm-up with a rising ceiling, then hold ${hrT[0]}–${hrT[1]} bpm${pwT?` (${pwT[0]}–${pwT[1]} W)`:""}; ${cd}-min cool-down with a falling ceiling.`);
  how.push(c.voice?`Spoken cues, ${a.freq==="important"?"corrections only":"frequent"}, ${c.tone} tone.`:"Screen cues only.");
  if(c.cadenceEnabled) how.push(`Cadence hints when effort is in order: ${c.cadRange[0]}–${c.cadRange[1]} rpm.`);
  measure.push("Time inside the heart-rate band (target ≥ 80%)","Heart-rate drift between halves at similar speed","Longest continuous block in zone"); if(c.powerCoaching) measure.push("Watts at the same heart rate vs previous rides (REAL once the XDS is verified)");
  if(a.heat==="yes") how.push("Advice: start before 8 am or after sunset to cut heat drift.");
  const alts=[{k:"shorter",n:`Shorter: ${Math.max(30,minutes-15)} min`},{k:"longer",n:`Longer: ${Math.min(long,minutes+15)} min`},{k:"rec",n:"Recovery spin 30 min"},...(a.limits==="none"&&a.style!=="steady"?[{k:"int",n:"Intervals: 4 × 4 min Zone 3"}]:[])];
  return {name,kind,minutes,hrT,pwT,why,how,measure,alts,success:a.success};
}

/* ---------------- screens ---------------- */
const SCR=["scrWelcome","scrQ","scrProfile","scrHome","scrLive","scrPost"];
function show(id,title){ SCR.forEach(s=>el(s).hidden=(s!==id)); el("appTitle").textContent=title||"Bike Computer"; const live=id==="scrLive"; ["cueCard","logCard","memoCard","kvCard"].forEach(c=>el(c).hidden=!live); el("cmpCard").hidden=!(P.completed); window.scrollTo({top:0,behavior:"smooth"}); }
function tag(cls,txt){ return `<i class="tag ${cls}">${txt}</i>`; }
function confTag(c){ return c.startsWith("CONFIRMED")?tag("conf","CONFIRMED"):c.startsWith("PROVISIONAL")?tag("prov","PROVISIONAL"):tag("sim","GENERIC"); }

function renderWelcome(){ el("appStep").textContent=""; el("scrWelcome").innerHTML=`<div class="hero"><p class="ey">First launch</p><h2 class="big">Let's build your personal cycling coach.</h2><p class="muted">About 30 quick questions, one at a time. Tap Skip or I don't know whenever you like — the coach will say what it still needs to learn. Nothing leaves this phone.</p><button class="btn play wide" id="startOb">START</button>${P.answers&&Object.keys(P.answers).length?`<button class="btn reset wide" id="resumeOb">RESUME WHERE I STOPPED</button>`:""}</div>`;
  el("startOb").onclick=()=>{ P.stepIndex=0; saveP(); renderStep(); }; const r=el("resumeOb"); if(r) r.onclick=()=>renderStep(); show("scrWelcome","Welcome"); }

function renderStep(){ const steps=visibleSteps(); if(P.stepIndex>=steps.length) P.stepIndex=steps.length-1; const s=steps[P.stepIndex]; const n=P.stepIndex+1, N=steps.length;
  el("appStep").textContent=`${n} / ${N}`; const a=A(); const cur=a[s.id];
  if(s.type==="summary"){ return renderSummary(); }
  let body="";
  const opts=typeof s.options==="function"?s.options(a):s.options;
  if(s.type==="choice") body=`<div class="opts">${opts.map(([k,l])=>`<button class="opt${cur===k?" on":""}" data-v="${k}">${l}</button>`).join("")}</div>`;
  if(s.type==="multi") body=`<div class="opts">${opts.map(([k,l])=>`<button class="opt${(cur||[]).includes(k)?" on":""}" data-m="${k}">${l}</button>`).join("")}</div>`;
  if(s.type==="number") body= s.slider? `<div class="num"><output id="numOut">${cur??Math.round((s.min+s.max)/3/5)*5} ${s.unit}</output><input type="range" id="numIn" min="${s.min}" max="${s.max}" step="${s.step||1}" value="${cur??Math.round((s.min+s.max)/3/5)*5}"></div>` : `<div class="num"><input type="number" id="numIn" min="${s.min}" max="${s.max}" value="${cur??""}" placeholder="${s.unit}" inputmode="numeric"> <span class="muted">${s.unit}</span></div>`;
  if(s.type==="two") body=`<div class="num two">${s.fields.map(([k,l,lo,hi])=>`<label>${l}<input type="number" data-k="${k}" min="${lo}" max="${hi}" value="${a[k]??""}" inputmode="numeric"></label>`).join("")}</div>`;
  if(s.type==="metric"){ const hows=s.hows||[["measured","Measured in a test"],["estimated","Estimated from workouts"],["app","Another app calculated it"],["unknown","I don't know"]]; const how=(cur&&cur.how)||""; body=`<div class="opts">${hows.map(([k,l])=>`<button class="opt${how===k?" on":""}" data-how="${k}">${l}</button>`).join("")}</div><div class="num" id="metricVal" ${how&&how!=="unknown"?"":"hidden"}><input type="number" id="numIn" min="${s.min}" max="${s.max}" value="${(cur&&cur.value)||""}" placeholder="${s.unit}" inputmode="numeric"> <span class="muted">${s.unit}</span></div>`; }
  el("scrQ").innerHTML=`<div class="qwrap"><div class="prog"><i style="width:${Math.round(n/N*100)}%"></i></div><h2 class="q">${s.q}</h2>${s.why?`<p class="why">${s.why}</p>`:""}${body}<div class="nav"><button class="btn reset" id="back" ${n===1?"disabled":""}>‹ BACK</button>${(s.skip||s.type==="metric"||s.type==="number"||s.type==="two"||s.type==="multi")?`<button class="btn reset" id="skip">${s.skip||(s.type==="metric"?"I don't know":"Skip")}</button>`:""}<button class="btn play" id="next">NEXT ›</button></div></div>`;
  show("scrQ","Your profile");
  const Q=el("scrQ");
  Q.querySelectorAll("[data-v]").forEach(b=>b.onclick=()=>{ a[s.id]=b.dataset.v; saveP(); advance(); });
  Q.querySelectorAll("[data-m]").forEach(b=>b.onclick=()=>{ let v=a[s.id]||[]; const k=b.dataset.m; if(k==="none"){ v=["none"]; } else { v=v.filter(x=>x!=="none"); v=v.includes(k)?v.filter(x=>x!==k):v.concat([k]); } a[s.id]=v; saveP(); renderStep(); });
  Q.querySelectorAll("[data-how]").forEach(b=>b.onclick=()=>{ const how=b.dataset.how; a[s.id]=Object.assign({},a[s.id]||{},{how}); if(how==="unknown"){ a[s.id]={how:"unknown",value:null}; saveP(); advance(); } else { saveP(); renderStep(); setTimeout(()=>{ const i=el("numIn"); if(i) i.focus(); },50); } });
  const ni=el("numIn"); if(ni&&s.slider) ni.oninput=()=>{ el("numOut").textContent=ni.value+" "+s.unit; };
  el("back").onclick=()=>{ P.stepIndex=Math.max(0,P.stepIndex-1); saveP(); renderStep(); };
  const sk=el("skip"); if(sk) sk.onclick=()=>{ if(s.type==="metric") a[s.id]={how:"unknown",value:null}; else if(s.type==="multi") a[s.id]=a[s.id]||[]; else delete a[s.id]; saveP(); advance(); };
  el("next").onclick=()=>{ if(s.type==="number"){ const v=+el("numIn").value; if(v>=s.min&&v<=s.max) a[s.id]=v; else if(!s.slider){ el("numIn").focus(); return; } }
    if(s.type==="two"){ Q.querySelectorAll("[data-k]").forEach(i=>{ const v=+i.value; if(v) a[i.dataset.k]=v; }); }
    if(s.type==="metric"){ const how=(a[s.id]||{}).how; if(!how){ return; } if(how!=="unknown"){ const v=+el("numIn").value; if(!(v>=s.min&&v<=s.max)){ el("numIn").focus(); return; } a[s.id]={how,value:v}; } }
    if(s.type==="choice"&&!a[s.id]) return;
    saveP(); advance(); };
}
function advance(){ P.stepIndex=Math.min(P.stepIndex+1,visibleSteps().length-1); saveP(); renderStep(); }

function profileRows(a,c){ const v=(x,alt="—")=>x==null||x===""?alt:x; const m=k=>{ const x=a[k]; if(!x||x.how==="unknown") return `<span class="muted">unknown</span>`; return `${x.value} ${tag(x.how==="measured"?"conf":"prov",x.how==="measured"?"MEASURED":x.how==="app"?"APP":x.how)}`; };
  return [["Main goal",goalName(primaryGoal(a))+((a.goals||[]).length>1?` <span class="muted">(+${(a.goals||[]).length-1} more)</span>`:"")],["3-month success",a.success?(successOptions(a).find(o=>o[0]===a.success)||[a.success,a.success])[1]:"—"],["Experience",v(a.experience)],["Age · height · weight",`${v(a.age)} · ${v(a.heightCm)} cm · ${v(a.weightKg)} kg`],["Rides now / days available",`${v(a.ridesNow)} / ${v(a.daysAvail)} per week`],["Typical · longest ride",`${v(a.typicalMin)} · ${v(a.longestMin)} min`],["Other exercise",(a.other||[]).join(", ")||"—"],["Rest days",(a.rest||[]).join(", ")||"no preference"],["Max HR",m("maxHr")],["Resting HR",m("restHr")],["Threshold HR",m("lthr")],["FTP",m("ftp")],["Natural cadence",m("cadence")],["Limiter · style",`${v(a.limiter)} · ${v(a.style)}`],["Heat",v(a.heat)],["Coaching",`${v(a.voice)} · ${v(a.freq)} · ${v(a.tone)} · ${v(a.detail)} · cadence ${v(a.cadAdvice)}`]]; }

function renderSummary(){ const a=A(); const c=deriveConfig(a); const r=recommend(a,c);
  el("appStep").textContent="summary";
  el("scrProfile").innerHTML=`<div class="qwrap"><p class="ey">Your rider profile</p><h2 class="q">Here is what the coach understood</h2>
  <div class="kv prof">${profileRows(a,c).map(([k,v])=>`<span>${k}</span><span>${v}</span>`).join("")}</div>
  <div class="box"><h3>Zone confidence</h3><p>${confTag(c.zoneConfidence)} ${c.zoneConfidence}. Zone 2 = <b>${c.hrTarget[0]}–${c.hrTarget[1]} bpm</b>${c.hrCap<c.hrTarget[1]?` (ceiling ${c.hrCap})`:""}${c.powerCoaching?` · ${Math.round(c.ftp*0.55)}–${Math.round(c.ftp*0.75)} W`:" · power targets off (FTP unknown)"}.</p></div>
  <div class="box"><h3>Recommended structure</h3><p><b>${r.name}</b>, ${r.minutes} min, ${c.warmupSec/60}-min warm-up, ${c.cooldownSec/60}-min cool-down, ${Math.min(+(a.daysAvail||3),(+(a.ridesNow||2))+1)} rides a week to start.</p></div>
  <div class="box"><h3>What the coach still needs to learn</h3><ul>${needs(a,c).map(x=>`<li>${x}</li>`).join("")}</ul></div>
  <div class="nav"><button class="btn reset" id="editProf">EDIT ANSWERS</button><button class="btn play" id="confirmProf">CONFIRM</button></div></div>`;
  el("editProf").onclick=()=>{ P.stepIndex=0; saveP(); renderStep(); };
  el("confirmProf").onclick=()=>{ P.completed=true; saveP(); applyProfile(); renderHome(); };
  show("scrProfile","Rider profile"); renderRules(c); }
function needs(a,c){ const n=[]; if(!c.zoneConfidence.startsWith("CONFIRMED")) n.push("Your real threshold heart rate — a 20-minute steady test, offered after 3 rides."); if(!c.ftpKnown) n.push("Your FTP — power meter verified under load first, then a 20-minute test."); else if(a.ftp.how!=="measured") n.push("Confirm FTP with a test (current value is "+a.ftp.how+")."); n.push("Whether you can hold the Zone 2 band on your route (first ride answers this)."); if(a.heat==="yes") n.push("How much heat lifts your heart rate (drift between halves)."); if(!(a.cadence&&a.cadence.how!=="unknown")) n.push("Your natural cadence (XDS sensor, first ride)."); return n; }

function renderHome(){ const a=A(); const c=deriveConfig(a); const r=recommend(a,c); const ov=P.override;
  const R=ov?Object.assign({},r,ov):r; el("appStep").textContent="";
  el("scrHome").innerHTML=`<div class="qwrap home"><p class="ey">Main goal</p><h2 class="q">${goalName(primaryGoal(a))}</h2>${a.success?`<p class="muted">Success in 3 months: ${(successOptions(a).find(o=>o[0]===a.success)||["",""])[1]}</p>`:""}
  <div class="box rec"><h3>Today's recommended workout ${ov?tag("prov","YOUR CHOICE"):""}</h3><div class="recname">${R.name}</div><div class="recline"><span>${R.minutes} min</span><span>${R.hrT[0]}–${R.hrT[1]} bpm</span><span>${R.pwT?R.pwT[0]+"–"+R.pwT[1]+" W":"power off"}</span></div>
   <h3 style="margin-top:8px">Why</h3><ul>${R.why.map(x=>`<li>${x}</li>`).join("")}</ul><h3>How the coach will guide it</h3><ul>${R.how.map(x=>`<li>${x}</li>`).join("")}</ul><h3>What it will measure</h3><ul>${R.measure.map(x=>`<li>${x}</li>`).join("")}</ul></div>
  <div class="alts"><span class="muted">Change workout:</span>${r.alts.map(x=>`<button class="opt small" data-alt="${x.k}">${x.n}</button>`).join("")}${ov?`<button class="opt small" data-alt="reset">Back to recommended</button>`:""}</div>
  <div class="nav"><button class="btn reset" id="profBtn">RIDER PROFILE</button><button class="btn play" id="startRide">START RIDE</button></div>
  <p class="muted small">Zones: ${confTag(c.zoneConfidence)} ${c.zoneConfidence}</p></div>`;
  el("profBtn").onclick=()=>renderSummary();
  el("startRide").onclick=()=>{ applyProfile(); show("scrLive","Live ride"); resetRide(); renderRules(c); renderCmpBox(); };
  el("scrHome").querySelectorAll("[data-alt]").forEach(b=>b.onclick=()=>{ const k=b.dataset.alt; if(k==="reset") P.override=null; else if(k==="shorter") P.override={minutes:Math.max(30,r.minutes-15),name:r.name+" (shorter)"}; else if(k==="longer") P.override={minutes:Math.min(a.longestMin||90,r.minutes+15),name:r.name+" (longer)"}; else if(k==="rec") P.override={minutes:30,name:"Recovery spin (Zone 1)",hrT:[c.hrTarget[0]-15,c.hrTarget[0]-1],pwT:null}; else if(k==="int") P.override={minutes:Math.max(45,r.minutes),name:"Intervals: 4 × 4 min Zone 3",hrT:[c.hrZoneEdges[1],c.hrZoneEdges[2]-1]}; saveP(); renderHome(); });
  show("scrHome","Home"); renderRules(c); renderCmpBox(); }

function applyProfile(){ const c=deriveConfig(A()); const keep=CFG; CFG=c; if(ST&&Object.keys(ST).length){ ORDER.forEach(id=>ST[id]=fullStats(id)); renderCmp(); renderMemoAll(); } }
function renderRules(c){ el("rules").innerHTML=`<div class="kv" style="margin-bottom:8px"><span>Zone 2</span><span>${c.hrTarget[0]}–${c.hrTarget[1]} bpm · cap ${c.hrCap}</span><span>Power</span><span>${c.powerCoaching?Math.round(c.ftp*0.55)+"–"+Math.round(c.ftp*0.75)+" W":"off"}</span><span>Warm-up / cool-down</span><span>${c.warmupSec/60} / ${c.cooldownSec/60} min</span><span>Cadence</span><span>${c.cadenceEnabled?c.cadRange[0]+"–"+c.cadRange[1]+" rpm":"off"}</span><span>Repeat spacing</span><span>${c.sameRepeat/1000} s · keep ${c.keepRepeat?c.keepRepeat/1000+" s":"once"}</span></div><ul class="rules">${c.rules.map(r=>`<li><b>${r.what}</b><br><span class="muted">${r.because}</span></li>`).join("")}</ul>`; }

/* run the engine silently over a ride with a given config and count cues */
function dryRun(cfg,id){ const saved=CFG; CFG=cfg; const S=SERIES[id], N=REAL[id].sec; const co=new Coach({mode:"ZONE2",usePower:cfg.powerCoaching,backoff:cfg.backoff,grace:cfg.grace,cadenceEnabled:cfg.cadenceEnabled,cadLow:cfg.cadRange[0],cadHigh:cfg.cadRange[1],sameRepeat:cfg.sameRepeat,keepRepeat:cfg.keepRepeat}); const counts={}; let inZone=0;
  for(let t=0;t<N;t++){ const ph=phaseAt(t,N,true); const cue=co.update(t*1000,ph,S.cad[t],S.hr[t],S.power[t],t,N); if(cue) counts[cue.type]=(counts[cue.type]||0)+1; const TG=targetsFor(ph,true,t,N); if(S.hr[t]>=TG.hr[0]&&S.hr[t]<=TG.hr[1]) inZone++; }
  CFG=saved; return {counts,inZonePct:Math.round(inZone/N*100),total:Object.values(counts).reduce((a,b)=>a+b,0)}; }
function renderCmpBox(){ if(!P.completed) return; const a=A(), c=deriveConfig(a); const g=dryRun(GENERIC,ride), p=dryRun(c,ride); const types=["WARMUP","PUSH_HARDER","KEEP_IT_UP","EASE_OFF","PEDAL_FASTER","PEDAL_SLOWER","QUIET","COOLDOWN"];
  el("cmpBox").innerHTML=`<div class="kv" style="grid-template-columns:1fr auto auto"><span class="muted">Replay of ${REAL[ride].date} (real HR)</span><span class="muted">generic</span><span class="muted">yours</span>
   <span>Zone 2 band</span><span>${GENERIC.hrTarget[0]}–${GENERIC.hrTarget[1]}</span><span>${c.hrTarget[0]}–${c.hrCap}</span>
   <span>Time inside band</span><span>${g.inZonePct}%</span><span>${p.inZonePct}%</span>
   ${types.map(t=>`<span>${t.replace("_"," ")}</span><span>${g.counts[t]||0}</span><span>${p.counts[t]||0}</span>`).join("")}
   <span><b>Total cues</b></span><span><b>${g.total}</b></span><span><b>${p.total}</b></span></div>
   <p class="muted" style="font-size:12px;margin:8px 0 0">The generic coach uses max HR 185 (Zone 2 = 111–129 bpm) and FTP 200 for everyone, so on your real rides it calls almost every minute "above target". Your coach uses the zones, ceiling, warm-up and speaking rules derived from your answers.</p>`; }

/* ---------------- post-ride ---------------- */
function rideResult(){ const R=REAL[ride], S=SERIES[ride]; let inZone=0; for(let t=0;t<R.sec;t++){ const TG=targetsFor(phaseAt(t,R.sec,true),true,t,R.sec); if(S.hr[t]>=TG.hr[0]&&S.hr[t]<=TG.hr[1]) inZone++; } const half=Math.floor(R.sec/2), m=x=>x.reduce((p,q)=>p+q,0)/x.length; const drift=((m(S.hr.slice(half))/m(S.hr.slice(300,half)))-1)*100; return {inZonePct:Math.round(inZone/R.sec*100),drift:drift.toFixed(0),avgHr:R.avgHr,sec:R.sec,km:R.km,cues:logEntries.filter(e=>e.type!=="NOTE").length}; }
window.onRideFinished=function(){ if(!P.completed) return; setTimeout(renderPost,600); };
el("finishBtn").addEventListener("click",()=>{ if(!P.completed){ return; } const R=REAL[ride]; playing=false; cancelAnimationFrame(raf); el("playBtn").textContent="▶ PLAY"; el("playBtn").className="btn play";
  if(t<R.sec){ const sc=el("scrub"); sc.value=R.sec; sc.dispatchEvent(new Event("input")); }   // fast-forward the rest of the ride through the engine
  renderPost(); });
function renderPost(){ const a=A(), c=deriveConfig(a); const res=rideResult(); const before=recommend(a,c);
  el("scrPost").innerHTML=`<div class="qwrap"><p class="ey">Ride complete</p><h2 class="q">${fmt(res.sec)} · ${res.km} km · avg ${res.avgHr} bpm ${tag("real","REAL")}</h2>
  <div class="kv prof"><span>Time inside your band</span><span>${res.inZonePct}% ${tag("real","REAL HR")}</span><span>HR drift, 2nd half vs 1st</span><span>+${res.drift}% ${tag("sim","EST.")}</span><span>Coach cues</span><span>${res.cues}</span></div>
  <h3 style="margin-top:12px">Two quick questions</h3>
  <p class="q small">How hard did that feel, 1 (easy) to 10 (maximal)?</p><div class="num"><output id="rpeOut">6</output><input type="range" id="rpe" min="1" max="10" value="6"></div>
  <p class="q small">What limited you?</p><div class="opts row"><button class="opt" data-l="legs">Legs</button><button class="opt" data-l="breathing">Breathing</button><button class="opt" data-l="tired">Tiredness</button><button class="opt" data-l="none">Nothing</button></div>
  <p class="q small">Do you feel recovered enough to ride again tomorrow?</p><div class="opts row"><button class="opt" data-r="yes">Yes</button><button class="opt" data-r="no">No</button><button class="opt" data-r="unsure">Not sure</button></div>
  <div class="nav"><button class="btn reset" id="skipPost">SKIP</button><button class="btn play" id="savePost">SAVE</button></div></div>`;
  let lim=null, rec=null; const S=el("scrPost"); S.querySelectorAll("[data-l]").forEach(b=>b.onclick=()=>{ lim=b.dataset.l; S.querySelectorAll("[data-l]").forEach(x=>x.classList.toggle("on",x===b)); }); S.querySelectorAll("[data-r]").forEach(b=>b.onclick=()=>{ rec=b.dataset.r; S.querySelectorAll("[data-r]").forEach(x=>x.classList.toggle("on",x===b)); });
  el("rpe").oninput=()=>{ el("rpeOut").textContent=el("rpe").value; };
  const finish=(withAnswers)=>{ const fb={date:new Date().toISOString().slice(0,10),ride,inZonePct:res.inZonePct,drift:+res.drift,avgHr:res.avgHr,sec:res.sec}; if(withAnswers){ fb.rpe=+el("rpe").value; fb.limiter=lim; fb.recovered=rec; } P.feedback.push(fb); P.override=null; saveP(); const after=recommend(a,c); renderNext(before,after,fb); };
  el("savePost").onclick=()=>finish(true); el("skipPost").onclick=()=>finish(false); show("scrPost","Post-ride"); }
function renderNext(before,after,fb){ const changed=before.name!==after.name||before.minutes!==after.minutes;
  el("scrPost").innerHTML=`<div class="qwrap"><p class="ey">Next workout</p><h2 class="q">${changed?"The recommendation changed":"The recommendation stands"}</h2>
  <div class="box"><h3>Before this ride</h3><p>${before.name} · ${before.minutes} min</p></div><div class="box rec"><h3>After this ride</h3><p><b>${after.name} · ${after.minutes} min</b></p><ul>${after.why.map(x=>`<li>${x}</li>`).join("")}</ul></div>
  <p class="muted small">Used: ${fb.rpe?`your effort ${fb.rpe}/10, limiter ${fb.limiter||"—"}, recovered ${fb.recovered||"—"}, `:""}time in band ${fb.inZonePct}% (real HR), drift +${fb.drift}% (estimated). Rides on record: ${P.feedback.length}.</p>
  <div class="nav"><button class="btn reset" id="againBtn">RIDE AGAIN</button><button class="btn play" id="homeBtn">HOME</button></div></div>`;
  el("homeBtn").onclick=()=>renderHome(); el("againBtn").onclick=()=>{ show("scrLive","Live ride"); resetRide(); }; show("scrPost","Next workout"); }

/* ---------------- boot ---------------- */
loadP();
// a reset link for testing the first-launch flow again
document.querySelector(".appbar").insertAdjacentHTML("beforeend",`<button class="linkbtn" id="resetAll" title="Clear saved answers and start over">reset</button>`);
el("resetAll").onclick=()=>{ P={answers:{},completed:false,feedback:[],stepIndex:0}; try{ localStorage.removeItem(STORE_KEY);}catch(_){ } CFG=Object.assign({},GENERIC); P.override=null; renderWelcome(); el("rules").textContent="Answer the onboarding questions in the phone and this panel fills with the exact rules your answers trigger."; };
renderCmp(); renderMemoAll(); renderQa(); renderFeat(); resetRide();
if(P.completed){ applyProfile(); renderHome(); } else if(Object.keys(P.answers).length){ renderStep(); } else renderWelcome();
