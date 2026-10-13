"""Original deterministic synthesis for SHARARA, CC0. No recordings or third-party sounds."""
import math, pathlib, random, struct, wave
out=pathlib.Path(__file__).resolve().parents[1]/'assets/audio'
out.mkdir(parents=True,exist_ok=True)
rate=24000
CUES=[('fire',520,.16),('attach',980,.12),('release',230,.18),('snap',140,.22),('creak',70,.3),
      ('crack_open',180,.9),('crack_close',420,.6),('hum',55,2.0),
      ('spark_spawn',700,.35),('spark_pop',900,.25),('spark_big_pop',240,.5),('drain',330,.6),('shard_lost',200,.5),
      ('gem_place',880,.35),('gem_hit',150,.3),('win',740,.9),('loss',120,.9),('thud',70,.3),('split',1200,.2)]
for cue, freq, seconds in CUES:
    rnd=random.Random(cue); data=[]
    n=int(rate*seconds)
    for i in range(n):
        t=i/rate; u=t/seconds
        env=1.0 if cue=='hum' else min(1,t/.008)*max(0,1-u)**1.6
        f=freq
        if cue in ('loss','snap','crack_close','gem_hit'): f=freq*(1-.45*u)
        elif cue=='fire': f=freq*(1+2.2*u)
        elif cue=='spark_spawn': f=freq*(1+1.5*u)
        elif cue=='spark_pop': f=freq*(1+.6*math.sin(math.tau*2*u))
        elif cue=='spark_big_pop': f=freq*(1-.6*u)
        elif cue=='crack_open': f=freq*(1+.4*math.sin(math.tau*5*u))
        elif cue=='drain': f=freq*(1+.5*u)
        elif cue=='win': f=freq*(1+.25*int(u*4))
        elif cue=='split': f=freq*(1+1.0*u)
        elif cue in ('thud',): f=freq*(1-.5*u)
        else: f=freq*(1+.4*u)
        s=math.sin(math.tau*f*t)*.22+math.sin(math.tau*f*1.5*t)*.07
        if cue in ['release','snap','fire','creak','crack_open','crack_close','spark_pop','spark_big_pop']: s+=rnd.uniform(-.06,.06)
        if cue=='drain': s*=.5+.5*math.sin(math.tau*14*t)
        if cue=='thud': s=math.sin(math.tau*f*t)*.3+rnd.uniform(-.12,.12)*max(0,1-t/.03)
        if cue=='creak': s=math.sin(math.tau*f*t*(1+.3*math.sin(math.tau*11*t)))*.18+rnd.uniform(-.1,.1)*.5
        if cue=='hum': s=(math.sin(math.tau*55*t)*.16+math.sin(math.tau*110*t)*.08+math.sin(math.tau*165*t)*.03)*(.8+.2*math.sin(math.tau*1.0*t))
        if cue=='spark_big_pop': s+=rnd.uniform(-.2,.2)*max(0,1-u*3)
        data.append(struct.pack('<h',int(32767*max(-1,min(1,s*env)))))
    with wave.open(str(out/(cue+'.wav')),'wb') as w:
        w.setparams((1,2,rate,0,'NONE','not compressed')); w.writeframes(b''.join(data))
print('Generated %d original mono 24 kHz cues' % len(CUES))
