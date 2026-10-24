import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
api = os.path.join(here, "api")
sys.path.insert(0, api)
os.chdir(api)
runpy.run_path(os.path.join(api, "desktop.py"), run_name="__main__")
