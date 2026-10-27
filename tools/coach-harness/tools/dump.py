import json,sys,os
d=sys.argv[1]
for pid in sys.argv[2:]:
    r=json.load(open(os.path.join(d,pid+'.json')))
    print('=====',pid,r['title'],'| PASS' if r['pass'] else '| FAIL')
    print(' inputs:', {k:v for k,v in r['inputs'].items() if k in ('trainingMode','priority','level','cyclingSessions','liftSessions','trainingDaysPerWeek','strengthSplit','planner.experience(effective)','planner.goal(effective)')})
    print(' availability:', ' | '.join(r['availability']))
    print(' consistency:', r['consistency'], 'trimmed:', r['trimmed'])
    for c in r['criteria']: print('  ', 'OK ' if c['pass'] else 'XX ', c['id'], c['kind'], '|', c['detail'][:300])
    print(' NEXT WEEK:')
    for w in r['nextWeek']:
        print('   ', w['date'], w['kind'], w['minutes'], w['title'], 'FIXED' if w['fixed'] else '', 'ADJ('+str(w.get('original'))+')' if w['coachAdjusted'] else '', 'ivl',w.get('intervalReps'))
        for e in w['entries']: print('       ', e['name'], '|', e.get('role'), '|', [(s['reps'], s.get('kg')) for s in e['sets']], 'RPE', e.get('targetRPE'), '| cyc:', (e.get('cycling') or '')[:60])
        if w['notes']: print('        notes:', ' / '.join(w['notes'])[:400])
    print(' THIS WEEK remaining:', [(w['date'],w['kind'],w['minutes'],'ADJ' if w['coachAdjusted'] else '') for w in r['thisWeekRemaining']])
    print(' adjustments:'); [print('   ', a['date'], a['workout'], a['change'], a['category'], '|', a['why'][:250]) for a in r['finalAdjustments']]
    print(' proposals:'); [print('   ', p['reason'], p['text'], '|', p['why'][:200]) for p in r['finalProposals']]
    print(' confidence', r['confidence'], 'acute', r.get('acuteLoad'), 'chronic', r.get('chronicLoad'))
    print(' findings:', r['findings'])
    print(' feedbackReq:', r.get('feedbackRequest')); print(' painAdvice:', r.get('painAdvice'))
    print(' hybrid next wk:', r['hybridFindingsNextWeek'], r['hybridProposalsNextWeek'])
    print(' history (last 6):'); [print('   ', h[:220]) for h in r['simulatedHistory'][-6:]]
    print(' events (last 3):'); [print('   ', e) for e in r['events'][-3:]]
