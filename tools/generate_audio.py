"""Original deterministic synthesis, CC0. No recordings or third-party sounds."""
import math, pathlib, random, struct, wave
out=pathlib.Path(__file__).resolve().parents[1]/'assets/audio'
out.mkdir(parents=True,exist_ok=True)
rate=24000
CUES=[('grab',660,.13),('dock',880,.25),('release',230,.18),('alert',440,.50),('win',740,.70),('loss',160,.65),
      ('fire',520,.16),('attach',980,.12),('snap',140,.22),('capture',620,.45),('spawn',300,.6),('drop',390,.2)]
for cue, freq, seconds in CUES:
    rnd=random.Random(cue); data=[]
    for i in range(int(rate*seconds)):
        t=i/rate; envelope=min(1,t/.008)*max(0,1-t/seconds)**1.6
        if cue in ('loss','snap'): f=freq*(1-.4*t/seconds)
        elif cue=='fire': f=freq*(1+2.2*t/seconds)
        elif cue=='capture': f=freq*(1+.9*math.sin(math.tau*3*t/seconds))
        elif cue=='spawn': f=freq*(1+.15*math.sin(math.tau*9*t))
        else: f=freq*(1+.4*t/seconds)
        sound=math.sin(math.tau*f*t)*.22+math.sin(math.tau*f*1.5*t)*.07
        if cue in ['release','alert','snap','fire']: sound+=rnd.uniform(-.06,.06)
        if cue=='alert': sound*=.5+.5*math.sin(math.tau*7*t)
        if cue=='spawn': sound*=.6+.4*math.sin(math.tau*2*t)
        if cue=='capture': sound+=math.sin(math.tau*f*2*t)*.08
        data.append(struct.pack('<h',int(32767*sound*envelope)))
    with wave.open(str(out/(cue+'.wav')),'wb') as wav:
        wav.setparams((1,2,rate,0,'NONE','not compressed')); wav.writeframes(b''.join(data))
print('Generated %d original mono 24 kHz cues' % len(CUES))
