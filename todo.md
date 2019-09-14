Next step:

move all of the below todo's to github issues, and clarify their milestone
and priority.

# More tests 
- make more thorough tests of various combinations of signals: resampling
in multiple places, changing length in multiple places, different channel
counts, etc... just to exercise the various combinations that will
be useful, and make sure codebase is better tested

- verify the efficiency of various operations
    (a big question is whether handling of channels with an array
     leads to many unecessary allocations, and if converting 
     all output to tuples within before calling `writesink` will help)

- performance:
    I'm pretty sure right now we are getting some dynamic calls
    to functions, given the arg splatting and unknown channel counts.
    (but who knows, maybe the compiler is smart enough...). I need to
    test out some specific cases: examine allocaiton. 
    This could invovle a rewrite of each signal type to include
    channel count information, to allow fast, type-stable
    tuples to be passed around and for the static call to the
    functions used as operators. 

# Documentation (after registration)

Prooferead documentation

# New Features / Refactoring (after registration)

move all features / refactoring to github issues

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