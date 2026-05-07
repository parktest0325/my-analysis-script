@echo off

set APKSIGNER_PATH=C:\Users\gmds\AppData\Local\Android\Sdk\build-tools\35.0.0\lib
set ZIPALIGN_PATH=C:\Users\gmds\AppData\Local\Android\Sdk\build-tools\35.0.0
set KEYSTORE_PATH=C:\Users\gmds\.android

set infile=%1
set aligned_file=%infile:apk=_aligned.apk%
set signed_file=%infile:apk=_signed.apk%

%ZIPALIGN_PATH%\zipalign.exe -f -v -p 4 "%infile%" "%aligned_file%"
java -jar %APKSIGNER_PATH%\apksigner.jar sign --ks=%KEYSTORE_PATH%\debug.keystore --ks-pass=pass:android --v4-signing-enabled false --out "%signed_file%" "%aligned_file%"
