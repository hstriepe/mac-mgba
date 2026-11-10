# Local mGBA patches

`scripts/build-libmgba.sh` applies every `*.patch` here (with `git apply`, in name order) to an APFS clone of the
`mgba/` submodule in `build/libmgba/src/`, so the submodule itself stays an untouched upstream checkout.

There are none so far: the player uses mGBA's core API as it is. Add one only when the core really needs a change,
keep it small, name it `NNNN-short-description.patch` (`git -C mgba diff > patches/0001-….patch`), and rerun the
build. When a submodule update makes a patch fail, refresh or drop it.
