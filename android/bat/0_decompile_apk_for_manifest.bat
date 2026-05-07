@echo off


set infile=%1
set infile_noext=%~n1
set infile_ext=%~x1

set TOOLS_PATH=C:\workspace\_TOOLS
set APKTOOL_PATH=%TOOLS_PATH%\apktool_2.9.3.jar
set AXMLEDITOR_PATH=%TOOLS_PATH%\AXMLEditor2.jar
set MANIFEST_PATH=%infile_noext%\AndroidManifest.xml
set MANIFEST_BACKUP=%MANIFEST_PATH%.bak
set OUTPUT_FILE="%infile_noext%_rebuild%infile_ext%" 

rmdir /q /s "%infile_noext%"
del "%OUTPUT_FILE%" 
java -jar "%APKTOOL_PATH%" d -r -s "%infile%"
java -jar "%AXMLEDITOR_PATH%" -attr -i application package debuggable true "%MANIFEST_PATH%" "%MANIFEST_BACKUP%"

del "%MANIFEST_PATH%"
move "%MANIFEST_BACKUP%" "%MANIFEST_PATH%"
