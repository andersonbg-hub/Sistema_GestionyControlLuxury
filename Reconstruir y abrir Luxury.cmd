@echo off
cd /d "%~dp0luxury-flutter-fuente"
call flutter pub get
if errorlevel 1 goto fallo
call flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/supabase.public.json --output=../web-conectado
if errorlevel 1 goto fallo
cd /d "%~dp0"
python servidor_local.py
exit /b 0
:fallo
echo.
echo No se pudo compilar. Revisa que Flutter 3.44.4 este en el PATH (flutter --version).
pause
