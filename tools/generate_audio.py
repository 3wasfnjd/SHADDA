"""Original deterministic synthesis, CC0. No recordings or third-party sounds."""
import math, pathlib, random, struct, wave
out=pathlib.Path(__file__).resolve().parents[1]/'assets/audio'
out.mkdir(parents=True,exist_ok=True)
rate=24000
for cue, freq, seconds in [('grab',660,.13),('dock',880,.25),('release',230,.18),('alert',440,.50),('win',740,.70),('loss',160,.65)]:
    rnd=random.Random(cue); data=[]
    for i in range(int(rate*seconds)):
        t=i/rate; envelope=min(1,t/.008)*max(0,1-t/seconds)**1.6
        f=freq*(1+.4*t/seconds) if cue!='loss' else freq*(1-.4*t/seconds)
        sound=math.sin(math.tau*f*t)*.22+math.sin(math.tau*f*1.5*t)*.07
        if cue in ['release','alert']: sound+=rnd.uniform(-.06,.06)
        if cue=='alert': sound*=.5+.5*math.sin(math.tau*7*t)
        data.append(struct.pack('<h',int(32767*sound*envelope)))
    with wave.open(str(out/(cue+'.wav')),'wb') as wav:
        wav.setparams((1,2,rate,0,'NONE','not compressed')); wav.writeframes(b''.join(data))
print('Generated six original mono 24 kHz cues')
