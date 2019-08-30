- efficiently handling resampling, so that e.g. signals defined by functions
    just get called with the new rate, rather than using interpolation
- use AxisArrays (not MetaArray) for better signal array representation
- allow for SampleBuf's
- handle filters iteratively to allow for infinite signals
- allow for missing sample rates, which can be resolved during
a signal operator, or during the call to `sink`

