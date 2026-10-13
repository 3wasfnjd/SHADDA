"""Original deterministic synthesis, CC0. No recordings or third-party sounds."""
import math, pathlib, random, struct, wave
out=pathlib.Path(__file__).resolve().parents[1]/'assets/audio'
out.mkdir(parents=True,exist_ok=True)
rate=24000
CUES=[('grab',660,.13),('dock',880,.25),('release',230,.18),('alert',440,.50),('win',740,.70),('loss',160,.65),
      ('fire',520,.16),('attach',980,.12),('snap',140,.22),('capture',620,.45),('spawn',300,.6),('drop',390,.2),
      ('step',95,.09),('step_heavy',60,.16),('creak',70,.3),('hum',55,2.0),('seal',420,.6),('thud',70,.3)]
for cue, freq, seconds in CUES:
    rnd=random.Random(cue); data=[]
    n=int(rate*seconds)
    for i in range(n):
        t=i/rate
        if cue=='hum':
            envelope=1.0  # seamless loop: integer cycles of 55 Hz over 2 s
        else:
            envelope=min(1,t/.008)*max(0,1-t/seconds)**1.6
        if cue in ('loss','snap'): f=freq*(1-.4*t/seconds)
        elif cue=='fire': f=freq*(1+2.2*t/seconds)
        elif cue=='capture': f=freq*(1+.9*math.sin(math.tau*3*t/seconds))
        elif cue=='spawn': f=freq*(1+.15*math.sin(math.tau*9*t))
        elif cue=='seal': f=freq*(1-.7*t/seconds)
        elif cue in ('step','step_heavy','thud'): f=freq*(1-.5*t/seconds)
        elif cue=='hum': f=freq
        else: f=freq*(1+.4*t/seconds)
        sound=math.sin(math.tau*f*t)*.22+math.sin(math.tau*f*1.5*t)*.07
        if cue in ['release','alert','snap','fire','creak','seal']: sound+=rnd.uniform(-.06,.06)
        if cue=='alert': sound*=.5+.5*math.sin(math.tau*7*t)
        if cue=='spawn': sound*=.6+.4*math.sin(math.tau*2*t)
        if cue=='capture': sound+=math.sin(math.tau*f*2*t)*.08
        if cue in ('step','step_heavy','thud'): sound=math.sin(math.tau*f*t)*.3+rnd.uniform(-.12,.12)*max(0,1-t/.03)
        if cue=='creak': sound=math.sin(math.tau*f*t*(1+.3*math.sin(math.tau*11*t)))*.18+rnd.uniform(-.1,.1)*.5
        if cue=='hum': sound=(math.sin(math.tau*55*t)*.16+math.sin(math.tau*110*t)*.08+math.sin(math.tau*165*t)*.03)*(.8+.2*math.sin(math.tau*1.0*t))
        data.append(struct.pack('<h',int(32767*max(-1,min(1,sound*envelope)))))
    with wave.open(str(out/(cue+'.wav')),'wb') as wav:
        wav.setparams((1,2,rate,0,'NONE','not compressed')); wav.writeframes(b''.join(data))
print('Generated %d original mono 24 kHz cues' % len(CUES))
