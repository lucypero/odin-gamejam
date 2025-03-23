# Voidcrawl - A game submission for odin's 7 day gamejam!

[Odin gamejam link](https://itch.io/jam/odin-7-day-jam)

This game was made in 7 days by Lucy and AttentiveColon

## Screenshots



## Tools used

- The [Odin](https://odin-lang.org/) programming language
- Started from [Karl's web template](https://github.com/karl-zylinski/odin-raylib-web)
- [Raylib library](https://www.raylib.com/)
- [LDtk](https://ldtk.io/)
- [Blender](https://www.blender.org/)

## Assets

- The Sound effects are from [freesound.org](https://freesound.org/)
- Everything else was made by us, including music and 3D assets.


## How to build

Desktop build:

`odin run source/main_desktop -show-debug-messages -define:RAYLIB_SHARED=true`

You'll need a new build of raylib as a dynamic library placed in the root directory. A critical bug was fixed after the latest release so the one shipped with Odin won't work. A dll is provided in this repository. It will work on Windows.
