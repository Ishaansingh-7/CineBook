import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
pythonw = Path(sys.executable).with_name("pythonw.exe")
launcher = here / "CineBook.pyw"
icon = here / "web" / "cinebook.ico"

script = f"""
$desktop = [Environment]::GetFolderPath('Desktop')
$s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'CineBook.lnk'))
$s.TargetPath = '{pythonw}'
$s.Arguments = '"{launcher}"'
$s.WorkingDirectory = '{here}'
$s.IconLocation = '{icon}'
$s.Description = 'CineBook movie ticket booking'
$s.Save()
"""

subprocess.run(["powershell", "-NoProfile", "-Command", script], check=True)
print("CineBook shortcut created on your desktop.")
