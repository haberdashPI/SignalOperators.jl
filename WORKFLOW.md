This documents my git workflow.

*Before version 0.2*: all commits are to master, and tags denote new, stable
releases of the 0.1 branch.

*Starting with the development of version 0.2 features*
    1. master includes the latest and greatest, working features
    2. release-x.y: stable branch for older release x.y, making it
       easy to backport any bug fixes
    3. feat-X branches contain new, WIP features, that may not yet compile
    and may be quite buggy
    4. fix-X branches contain new, WIP bug fixes, that may not yet compile
    5. refactor-X branches contain new, WIP refactoring of code that may not
    yet compile

New releases of the most recent version # are tagged on master.

When a `feat`, `fix` or `refactor` branch is merged, it should first be rebased into commits that conform to the [Conventiional Commit](https://www.conventionalcommits.org/en/v1.0.0-beta.2/#summary) standard.