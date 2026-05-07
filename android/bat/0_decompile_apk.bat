@echo off

set TOOLS_PATH=C:\workspace\_TOOLS
set APKTOOL_PATH=%TOOLS_PATH%\apktool_2.9.3.jar
set infile=%1

java -jar "%APKTOOL_PATH%" d "%infile%"
