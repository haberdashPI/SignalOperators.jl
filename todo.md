# Breaking
- use AxisArrays (not MetaArray) for better signal array representation
- allow for missing sample rates, which can be resolved during
a signal operator, or during the call to `sink` (not technically breaking
but makes a big difference in terms of API flexibility, so should be done soon)

# New Features
- efficiently handling resampling, so that e.g. signals defined by functions
    just get called with the new rate, rather than using interpolation
- allow for SampleBuf's
- handle filters iteratively to allow for infinite signals

