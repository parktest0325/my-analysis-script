@echo off

set TOOLS_PATH=C:\workspace\_TOOLS
set APKTOOL_PATH=%TOOLS_PATH%\apktool_2.9.3.jar
set infile=%1
set infile_noext=%~n1
set infile_ext=%~x1


java -jar "%APKTOOL_PATH%" b "%infile_noext%" -o "%infile_noext%_rebuild%infile_ext%"
pause
