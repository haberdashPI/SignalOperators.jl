- efficiently handling resampling, so that e.g. signals defined by functions
    just get called with the new rate, rather than using interpolation
- allow for missing sample rates, which can be resolved during
a signal operator, or during the call to `sink`
