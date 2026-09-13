@echo off
chcp 65001 >nul
rem 把「轻启」一个主 HAP 安装到你的鸿蒙手机（Windows）。
rem 用法：把本脚本和一个 .hap 放在同一目录，双击运行，或：
rem   install-to-user-device.bat
rem 找不到 hdc 时，请设置 DEVECO_APP 为 DevEco Studio 安装目录。

setlocal
set "HAP_DIR=%~dp0"
set "APP_HAP=%HAP_DIR%entry-default-signed.hap"

if defined HDC_BIN (
  set "HDC=%HDC_BIN%"
) else if exist "%HAP_DIR%hdc.exe" (
  rem 使用用户自行准备的官方 hdc。
  set "HDC=%HAP_DIR%hdc.exe"
) else (
  set "HDC=%DEVECO_APP%\sdk\default\openharmony\toolchains\hdc.exe"
)
if not exist "%HDC%" if exist "%LOCALAPPDATA%\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" (
  set "HDC=%LOCALAPPDATA%\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
)

if not exist "%HDC%" (
  echo 找不到 hdc，请设置 DEVECO_APP 为 DevEco Studio 安装目录，或用 HDC_BIN 指定 hdc 路径。
  exit /b 2
)
if not exist "%APP_HAP%" (
  echo 缺少 entry-default-signed.hap，请将本脚本和一个 .hap 放在同一目录。
  exit /b 2
)
echo 正在安装轻启单包...
set "RESULT=%TEMP%\quietstart-install-%RANDOM%.txt"
"%HDC%" list targets >"%RESULT%" 2>&1
if errorlevel 1 (
  type "%RESULT%"
  del "%RESULT%"
  exit /b 2
)
set "DEVICE="
set /a DEVICE_COUNT=0 >nul
for /f "usebackq tokens=1,2" %%A in ("%RESULT%") do (
  if "%%B"=="" if not "%%A"=="[Empty]" (
    set "DEVICE=%%A"
    set /a DEVICE_COUNT+=1 >nul
  )
)
if not "%DEVICE_COUNT%"=="1" (
  echo 请仅连接一台已授权的手机，并断开额外的电脑无线调试连接。
  type "%RESULT%"
  del "%RESULT%"
  exit /b 2
)
"%HDC%" -t "%DEVICE%" install -r "%APP_HAP%" >"%RESULT%" 2>&1
set "INSTALL_CODE=%ERRORLEVEL%"
type "%RESULT%"
findstr /c:"install bundle successfully" "%RESULT%" >nul
set "CHECK_CODE=%ERRORLEVEL%"
findstr /l /c:"[Fail]" "%RESULT%" >nul
set "FAIL_CODE=%ERRORLEVEL%"
del "%RESULT%"
if not "%INSTALL_CODE%"=="0" exit /b 1
if "%FAIL_CODE%"=="0" exit /b 1
if not "%CHECK_CODE%"=="0" (
  echo 安装未成功，请检查签名授权与设备连接。
  exit /b 1
)
echo 轻启已安装。打开应用，按向导开启无线调试；首次连接会自动安装工作模块。
endlocal
