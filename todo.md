# Changes (before registration)
+ use AxisArrays (not MetaArray) for better signal array representation
+ revise sink interface (allow for fast loops, but with chunking (for e.g. filters))
    - test new implementation
+ allow for missing sample rates, which can be resolved during
a signal operator, or during the call to `sink` (not technically breaking
but makes a big difference in terms of API flexibility, so should be done soon)
    - test missing sample rates
+ once missing sample rates work, allow for non-signal objects in more cases (and implicity assume a missing samplerate)
    - test non-signal objects
+ efficiently handling resampling, so that e.g. signals defined by functions
    just get called with the new rate, rather than using interpolation
    - test it!
+ handle filters iteratively to allow for infinite signals
    - test it
+ allow for missing samplerates in filters (need to resolve
    filter coefficeints lazzily)
    - test it!
+ allow for SampleBuf's
- allow for lazy normpower

# More tests (before registration)
- make sure I've fully tested logic of the more complicated
  signals that use checkpoints
- test with frame units 
- verify exact cutting of stimuli by frames
- test with fixed point numbers
- make more thorough tests of various combinations of signals: resampling
in multiple places, changing length in multiple places, different channel
counts, etc... just to exercise the various combinations that will
be useful, and make sure codebase is better tested

# New Features (after registration)
- allow for unknown length signals, e.g. streaming to a device
    and reading from a file
- allow online normpower
- support LibSndFile
- allow for chunked functions as input to `signal`