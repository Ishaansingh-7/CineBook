@echo off
cd /d "%~dp0"
git rm -q --cached --ignore-unmatch push_to_github.cmd >nul
git add -A
git commit -m "Remove local helper files and simplify README"
git push origin main
echo.
echo Done: https://github.com/Ishaansingh-7/CineBook
pause
(goto) 2>nul & del "%~f0"
