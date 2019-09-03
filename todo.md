# Breaking (before registration)
+ use AxisArrays (not MetaArray) for better signal array representation
- allow for missing sample rates, which can be resolved during
a signal operator, or during the call to `sink` (not technically breaking
but makes a big difference in terms of API flexibility, so should be done soon)

# More tests (before registration)
- make more thorough tests of various combinations of signals: resampling
in multiple places, changing length in multiple places, different channel
counts, etc... just to exercise the various combinations that will
be useful, and make sure codebase is better tested

# New Features (after registration)
- efficiently handling resampling, so that e.g. signals defined by functions
    just get called with the new rate, rather than using interpolation
- allow for SampleBuf's
- handle filters iteratively to allow for infinite signals

