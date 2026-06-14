import os
import re
import glob

files = glob.glob('assets/ribbons/*.svg')
for f in files:
    with open(f, 'r') as file:
        content = file.read()
    
    colors = set(re.findall(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', content))
    
    for r, g, b in colors:
        if r == g and g == b and int(r) < 250:
            content = content.replace(f'rgb({r},{g},{b})', 'rgba(0,0,0,0.35)')
    
    with open(f, 'w') as file:
        file.write(content)
print("Shadows fixed safely.")
