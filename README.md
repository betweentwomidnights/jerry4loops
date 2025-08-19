# jerry4loops

an experimental ios app for real-time loop generation and jamming

## what it does

jerry4loops uses ai models to generate synchronized drum and instrument loops that you can jam with in real-time. built around grid-aligned 4/8 bar loops with instant swapping and style transfer capabilities.

## the tech stack

### ai models
- **stable-audio-open-small**: generates the initial loops
  - [model on huggingface](https://huggingface.co/stabilityai/stable-audio-open-small)
  - [our api wrapper](https://github.com/betweentwomidnights/stable-audio-api) (runs on T4 gpu)

- **magentaRT**: handles real-time style transfer and iteration
  - [original repo](https://github.com/magenta/magenta-realtime) (dependency hell)
  - [our simplified api](https://huggingface.co/spaces/thecollabagepatch/magenta-retry/tree/main)

### architecture notes
since websockets are a pain in ios, our apis use http requests with project-specific optimizations for grid-aligned loops. stable-audio-open-small is highly bpm-aware, so we append global bpm to every prompt.

## how it works

1. **generate**: create drums + instrument loops with saos
2. **sync**: loops play simultaneously and swap at loop boundaries  
3. **style transfer**: combine both loops as input for new variations
4. **jam**: toggle magentaRT to get endless "next 4/8 bars" with style embed updates

## features

### audio processing
- lp filter and reverb knobs for both drum and instrument loops
- lfo toggle on instrument filter creates a "dance wah" effect
- stutter effect on drums (hold button for 16th note rhythmic stuttering)

### loop management  
- **saved loops**: save and recall loops organized by current global bpm
- **instant swapping**: replace loops at loop boundaries from your saved grid
- **style transfer**: use combined audio as input for new generations

## current todos

### core functionality
- save/load projects (global bpm, saved loops grid, starting loops, settings, prompts)
- better prompt engineering (replace the braindead dice button)
- lfo/filter/reverb settings ui (double tap configuration maybe)

### ux improvements  
- record session feature for sharing/exporting jams
- onboarding/tutorial (fear i've made another instrument only i know how to play)

### model improvements
- settings to select fine-tunes for saos and magentaRT hosted on hf
- need to actually fine-tune both models

## caveats and limitations

### resource requirements
magentaRT needs 48gb gpu ram on L40S for real-time performance. this makes the app:
- not ready for app store (scalability issues)
- expensive to run ($1.80/hour if you duplicate the hf space)  
- not viable for concurrent users without major infrastructure changes

### current status
this is research/experiment territory right now. tpus might be the path to actual scalability, or we need some serious gpu subsidies.

## contributing 

### models
if you have fine-tunes of magentaRT or stable-audio-open-small, please share them on huggingface so we can integrate them. too many of us hoard our finetunes. keep ai music open source!

### development
contributions welcome for ux, optimization, or infrastructure improvements.

### collaboration
- twitter: [@thepatch_kev](https://twitter.com/thepatch_kev)  
- email: kev@thecollabagepatch.com
- especially interested in hearing from google or stability folks about bringing this to app stores

## getting started

1. clone this repo
2. open `jerry_for_loops.xcodeproj` in xcode
3. make sure you have access to the api endpoints (or set up your own)
4. build and run on ios device/simulator

note: you'll need your own api setup unless we work out some kind of shared infrastructure.
