This documents my git workflow.

*Before version 0.2*: all commits are to master, and tags denote new, stable
releases of the 0.1 branch.

*Starting with the development of version 0.2 features*
    1. master includes the latest and greatest, working features
    2. release-x.y: stable branch for older release x.y, making it
       easy to backport any bug fixes
    3. features branchs contain new, WIP features, that may not yet compile
    and may be quite buggy
