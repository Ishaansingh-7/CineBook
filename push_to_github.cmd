@echo off
cd /d "%~dp0"
where git >nul 2>nul || (echo Git is not installed. Install it from https://git-scm.com/download/win and run this again. & pause & exit /b 1)
if exist api\__pycache__ rmdir /s /q api\__pycache__
if not exist .git git init -b main
git config user.name >nul || git config user.name "Ishaan Singh"
git config user.email >nul || git config user.email "Ishaansingh-7@users.noreply.github.com"
git add -A
git commit -m "CineBook: movie ticket booking system (Oracle PL/SQL, FastAPI, desktop web app)"
git branch -M main
git remote remove origin 2>nul
git remote add origin https://github.com/Ishaansingh-7/CineBook.git
git push -u origin main
echo.
echo Done: https://github.com/Ishaansingh-7/CineBook
pause
