import os
import re
import glob

def process_svgs():
    files = glob.glob('assets/ribbons/*.svg')
    for f in files:
        with open(f, 'r') as file:
            content = file.read()
        
        # Find viewBox
        match = re.search(r'viewBox="([^"]+)"', content)
        viewbox = match.group(1) if match else "Unknown"
        
        # Find all rgb colors
        colors = set(re.findall(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', content))
        
        greys = []
        for r, g, b in colors:
            r, g, b = int(r), int(g), int(b)
            # If color is grayish
            diff = max(r, g, b) - min(r, g, b)
            if diff < 20 or (r > 130 and g == b): # catching some weird tinted greys
                greys.append(f'rgb({r},{g},{b})')
        
        print(f"{os.path.basename(f)}: ViewBox {viewbox}, Greys: {greys}")
        
        # Replace greys with translucent black
        for grey in greys:
            # We want to replace rgb(...) with rgba(0,0,0,0.4)
            # Some properties like fill don't support rgba directly in older SVG viewers but flutter_svg handles it perfectly.
            # But let's just do it.
            # We need to replace exactly this string
            content = content.replace(grey, 'rgba(0,0,0,0.35)')
        
        # Also let's replace any stroke="rgb(...)" if they are grey
        # (the replace above does it globally)
        
        with open(f, 'w') as file:
            file.write(content)

process_svgs()
