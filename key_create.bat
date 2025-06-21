@echo off
REM Убедитесь, что в PATH у вас добавлена папка %JAVA_HOME%\bin,
REM чтобы команда keytool резолвилась корректно.

set KEYSTORE_NAME=keystore.jks
set STOREPASS=qwerty
set KEYPASS=qwerty

keytool -genkeypair ^
  -v ^
  -keystore "%KEYSTORE_NAME%" ^
  -keyalg RSA ^
  -keysize 2048 ^
  -validity 10000 ^
  -alias app ^
  -storepass "%STOREPASS%" ^
  -keypass "%KEYPASS%" ^
  -dname "CN=Test, OU=Dev, O=Test, L=City, S=Region, C=EN"

pause
