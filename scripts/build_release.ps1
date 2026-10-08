# Build script for Bar Rooms Trivia: builds web distribution, Android APK, and Android App Bundle (.aab)
Write-Host "==> Building Web Distribution (Vite)..." -ForegroundColor Cyan
npm run build

Write-Host "`n==> Building Android Release APK..." -ForegroundColor Cyan
& "C:\src\flutter\bin\flutter.bat" build apk

Write-Host "`n==> Building Android App Bundle (.aab)..." -ForegroundColor Cyan
& "C:\src\flutter\bin\flutter.bat" build appbundle

Write-Host "`n==> Build Complete! Output Artifacts:" -ForegroundColor Green
Get-Item build\app\outputs\flutter-apk\app-release.apk, build\app\outputs\bundle\release\app-release.aab | Select-Object FullName, Length, LastWriteTime
