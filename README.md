# Voidcrawl - A game submission for odin's 7 day gamejam!

This game was made in 7 days by Lucy and AttentiveColon for the [Odin 7 day game jam](https://lucypero.itch.io/voidcrawl)

[Play it on the web!](https://lucypero.itch.io/voidcrawl)

## Screenshots

![main_desktop_EA6UsKpsmf](https://github.com/user-attachments/assets/479cd09c-0e2f-4535-9c8b-af2b63554fae)
![main_desktop_reTwC6z5JL](https://github.com/user-attachments/assets/c40a0bf2-b2e7-4927-af42-56066bd53b02)
![main_desktop_i88gJ77sNi](https://github.com/user-attachments/assets/446541ad-9711-4a75-929e-1463ce86b38e)


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
