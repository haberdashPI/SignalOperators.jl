# More tests 
- make more thorough tests of various combinations of signals: resampling
in multiple places, changing length in multiple places, different channel
counts, etc... just to exercise the various combinations that will
be useful, and make sure codebase is better tested

- verify the efficiency of various operations
    (a big question is whether handling of channels with an array
     leads to many unecessary allocations, and if converting 
     all output to tuples within before calling `writesink` will help)

# Documentation (after registration)

document all public functions
 - TODO: list these all of these here

provide an overview of functions and example processing chains

introduce concepts of 
    - piping signals
    - unitful values
    - assumed units,
    - missing sample rates

# New Features / Refactoring (after registration)

move all features / refactoring to github issues

- fix bug in `format` where we have `nchannels(x) == 0`
- raise a warning when the sampling rate is too low to 
    to handle a filter's settings.
- there are a lot of internals that are pretty ugly,
    clean them up and document the procedure to create
    new computed signals
        - inconsistent/poor names
        - redundant code
        - confusing internal API's
- support LibSndFile
- improve the printout of signal operators (very ugly right now)
- allow chunked functions as input to `signal`
- allow for unknown length signals, e.g. streaming to a device
    and reading from a file
- allow online normpower