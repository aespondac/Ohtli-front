import os
import re
import glob
import colorsys

def shift_color_silver(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r/255.0, g/255.0, b/255.0)
    
    # Slight cool blueish tint for metallic silver
    new_h = 210 / 360.0
    new_s = 0.05
    
    # Linear scale to preserve exact contrasts without clipping to white
    # V goes from ~0.2 (dark shadow) to ~0.95 (bright highlight)
    new_v = (v * 0.75) + 0.2
    
    nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, new_v)
    return int(nr*255), int(ng*255), int(nb*255)

files = glob.glob('assets/ribbons/Ribbon_*.svg')
files = [f for f in files if '_' not in os.path.basename(f).replace('Ribbon_', '')]

for f in files:
    with open(f, 'r') as file:
        original_content = file.read()
    
    colors = set(re.findall(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', original_content))
    content = original_content
    for r_str, g_str, b_str in colors:
        r, g, b = int(r_str), int(g_str), int(b_str)
        if r == g == b or max(r,g,b) < 30:
            continue
            
        nr, ng, nb = shift_color_silver(r, g, b)
        content = content.replace(f"rgb({r_str},{g_str},{b_str})", f"rgb({nr},{ng},{nb})")
        
    out_name = f.replace('.svg', '_silver.svg')
    with open(out_name, 'w') as out:
        out.write(content)

print("Silver ribbons regenerated with perfectly preserved tones.")
