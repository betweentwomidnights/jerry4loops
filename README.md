# jerry4loops

an experimental ios app for real-time loop generation and jamming. somewhere between dj-ing and playing live music...live coding but it's with ai models'

generate synchronized drum and instrument loops that you can save and swap in and out. built around grid-aligned 4/8 bar loops. swap in fresh or saved loops at the next bar boundary. have magenta perform a continuous jam on the instrument loop while you fiddle around with knobs and generate new drum loops. record your jam.



- **stable-audio-open-small**: generates the initial loops
  - [model on huggingface](https://huggingface.co/stabilityai/stable-audio-open-small)
  - [our api wrapper](https://github.com/betweentwomidnights/stable-audio-api) (runs on T4 gpu)

- **magentaRT**: handles real-time style transfer and iteration
  - [original repo](https://github.com/magenta/magenta-realtime) (dependency hell)
  - [our simplified api](https://huggingface.co/spaces/thepatch/magenta-retry) - now duplicable!

### architecture notes
since websockets are a pain in ios, our apis use http requests with project-specific optimizations for grid-aligned loops. stable-audio-open-small is highly bpm-aware, so we append global bpm to every prompt.

## how it works

1. **generate**: create drums + instrument loops with saos
2. **sync**: loops play simultaneously and swap at loop boundaries
3. **style transfer**: combine both loops as input for new variations
4. **jam**: toggle magentaRT to get endless "next 4/8 bars" with style embed updates
5. **model switcher**: swap and load any magenta finetune hosted on hf

## features (sept 20 update)

### audio processing
- lp filter and reverb knobs for both drum and instrument loops
- lfo toggle on instrument filter creates a "dance wah" effect (currently a bit broken at high frequencies)
- stutter effect on drums (hold button for 16th note rhythmic stuttering - needs work on some drum patterns)


### loop management
- **saved loops**: save and recall loops organized by current global bpm
- **instant swapping**: replace loops at loop boundaries from your saved grid
- **style transfer**: use combined audio as input for new generations

### new stuff
- **model switching**: switch between any magentaRT finetune on huggingface via the studio menu
- **custom backends**: point to your own magentaRT api instance (duplicate our hf space with L40s hardware)
- **session recording**: record your jams and share them (basic functionality, files get huge)

## current todos

### core functionality
- save/load projects (global bpm, saved loops grid, starting loops, settings, prompts)
- lfo/filter/reverb settings ui (triple tap tap configuration maybe)
- fix the filter lfo wah reversal at high frequencies
- improve stutter effect so it's more dynamic and guarantees something cool happens.
-

### ux improvements
- video sharing and better compression for recorded jams
- onboarding/tutorial (everything i build is fun but only if you figure out how to use it)
- testflight build, maybe just yolo to app store

### model improvements
- more finetunes! use the [colab notebook](https://colab.research.google.com/github/magenta/magenta-realtime/blob/main/notebooks/Magenta_RT_Finetune.ipynb) and follow the hf space instructions for proper tarball uploads
- settings to select fine-tunes for saos (magentaRT switching already implemented)

## caveats and limitations

### resource requirements
magentaRT needs substantial gpu resources for real-time performance:
- L40s recommended for huggingface space duplication ($1.80/hour)
- 5090 locally with ngrok/zrok might work
- not ready for app store scalability without major infrastructure changes

### current status
this is research/experiment territory right now. tpus might be the path to actual scalability for hosted use, or we need some serious gpu subsidies.

## contributing

### models
if you have fine-tunes of magentaRT or stable-audio-open-small, please share them on huggingface so we can integrate them. too many of us hoard our finetunes. keep ai music open source!

the [finetuning notebook](https://colab.research.google.com/github/magenta/magenta-realtime/blob/main/notebooks/Magenta_RT_Finetune.ipynb) makes it pretty straightforward to train your own magentaRT models.

### development
contributions welcome for ux, optimization, or infrastructure improvements.

### collaboration
- twitter: [@thepatch_kev](https://twitter.com/thepatch_kev)
- email: kev@thecollabagepatch.com
- youtube tutorials: [thepatch_dev](https://youtube.com/@thepatch_dev) (major todo - need to actually make videos)
- especially interested in hearing from google or stability folks about bringing this to app stores

## getting started

1. clone this repo
2. open `jerry_for_loops.xcodeproj` in xcode
3. duplicate our [huggingface space](https://huggingface.co/spaces/thepatch/magenta-retry) with L40s hardware
4. update the backend url in the app's studio menu to point to your instance
5. build and run on ios device/simulator
