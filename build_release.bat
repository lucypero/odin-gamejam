@REM @echo off

set "projectName=MyProgram"  // Replace with your project name
set "buildDir=build"        // Replace with your build directory
set "releaseDir=release"      // Replace with your release directory
set "executable=%buildDir%\%projectName%.exe" // Path to your executable

echo Creating release directory...
if not exist "%releaseDir%" (
    mkdir "%releaseDir%"
)

xcopy "assets" "%releaseDir%\assets\" /E /I /Y
copy "raylib.dll" "%releaseDir%\"
odin build source/main_desktop -o:speed -define:RAYLIB_SHARED=true -out:%releaseDir%/lucycrawl.exe
