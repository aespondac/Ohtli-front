import os
import re
import glob
import colorsys

def shift_color(r, g, b, target_h, target_s, is_silver=False):
    # Convert to hsv
    h, s, v = colorsys.rgb_to_hsv(r/255.0, g/255.0, b/255.0)
    
    if is_silver:
        # Silver: hue 0, sat 0, slightly boost value
        new_h = 0
        new_s = 0
        new_v = min(1.0, v * 1.2 + 0.2)
    else:
        # For gold/rosegold: change hue, scale saturation
        new_h = target_h
        # Boost saturation a bit for rich gold
        new_s = min(1.0, s * target_s)
        new_v = v
        
    nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, new_v)
    return int(nr*255), int(ng*255), int(nb*255)

files = glob.glob('assets/ribbons/Ribbon_*.svg')
# Filter out already generated ones just in case
files = [f for f in files if '_' not in os.path.basename(f).replace('Ribbon_', '')]

for f in files:
    with open(f, 'r') as file:
        original_content = file.read()
    
    # Extract all rgb
    colors = set(re.findall(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', original_content))
    
    for variant, (th, ts, is_silver) in {
        'gold': (45/360.0, 1.2, False),
        'silver': (0, 0, True),
        'rosegold': (345/360.0, 0.6, False)
    }.items():
        content = original_content
        for r_str, g_str, b_str in colors:
            r, g, b = int(r_str), int(g_str), int(b_str)
            
            # Don't tint pure greys (shadows) or blacks
            if r == g == b or max(r,g,b) < 30:
                continue
                
            nr, ng, nb = shift_color(r, g, b, th, ts, is_silver)
            # Replace globally for this specific exact rgb string
            old_str = f"rgb({r_str},{g_str},{b_str})"
            new_str = f"rgb({nr},{ng},{nb})"
            content = content.replace(old_str, new_str)
            
        out_name = f.replace('.svg', f'_{variant}.svg')
        with open(out_name, 'w') as out:
            out.write(content)

print("Generated gold, silver, and rosegold variants.")
