"""Three original trail-network sketches. Black strokes are paths, not walls."""
from collections import deque
from pathlib import Path
import html
import json
import math
import random
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
N = 18
W, H = 1200, 1410
INK, BLUE, GOLD = '#17191c', '#315d9a', '#95641b'
REGULAR = 'C:/Windows/Fonts/arial.ttf'
BOLD = 'C:/Windows/Fonts/arialbd.ttf'


def edge(a, b):
    return tuple(sorted((tuple(a), tuple(b))))


def carve(region, seed, vertical=False):
    rng = random.Random(seed)
    allowed = set(region)
    stack = [min(allowed)]
    seen, edges = {stack[0]}, set()
    while stack:
        x, y = stack[-1]
        choices = [(x+dx, y+dy) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))
                   if (x+dx, y+dy) in allowed and (x+dx, y+dy) not in seen]
        if choices:
            if vertical and rng.random() < .7:
                options = [p for p in choices if p[0] == x]
                target = rng.choice(options or choices)
            else:
                target = rng.choice(choices)
            edges.add(edge(stack[-1], target))
            seen.add(target)
            stack.append(target)
        else:
            stack.pop()
    assert seen == allowed
    return edges


def extra_edges(edges, region, count, seed):
    rng = random.Random(seed)
    allowed = set(region)
    choices = [edge(p, q) for p in sorted(allowed) for q in ((p[0]+1,p[1]),(p[0],p[1]+1))
               if q in allowed and edge(p,q) not in edges]
    rng.shuffle(choices)
    edges.update(choices[:count])


def configurations():
    all_nodes = {(x,y) for x in range(N) for y in range(N)}
    quarter = set()
    for i, (x0,y0) in enumerate(((0,0),(9,0),(0,9),(9,9))):
        region = {(x,y) for x in range(x0,x0+9) for y in range(y0,y0+9)}
        quarter |= carve(region, 110+i)
        extra_edges(quarter, region, 2, 210+i)
    bridges_a = [edge((8,3),(9,3)), edge((3,8),(3,9)),
                 edge((14,8),(14,9)), edge((8,14),(9,14))]
    quarter.update(bridges_a)

    snakes = set()
    for i, x0 in enumerate((0,9)):
        region = {(x,y) for x in range(x0,x0+9) for y in range(N)}
        snakes |= carve(region, 301+i, vertical=True)
        extra_edges(snakes, region, 2, 401+i)
    bridges_b = [edge((8,y),(9,y)) for y in (3,9,14)]
    snakes.update(bridges_b)

    weave = carve(all_nodes, 514)
    extra_edges(weave, all_nodes, 22, 615)
    desired = [((3,4),(4,4)), ((12,8),(13,8)), ((6,13),(7,13))]
    barns_c = [min(weave, key=lambda e: math.dist(e[0], a) + math.dist(e[1], b))
               for a,b in desired]
    assert len(set(barns_c)) == 3
    return [
        dict(number=1, title='Четыре сектора', subtitle='Отдельные начальные зоны и несколько переходов между ними',
             edges=quarter, gapx=40, gapy=40, exit=(11,0), barns=bridges_a[:3],
             keys=[(5,5),(12,11),(5,14)]),
        dict(number=2, title='Две извилистые ветви', subtitle='Два длинных маршрута, связанные тремя проходными сараями',
             edges=snakes, gapx=40, gapy=0, exit=(6,0), barns=bridges_b,
             keys=[(5,7),(13,10),(7,15)]),
        dict(number=3, title='Больше развилок и обходов', subtitle='Единая сеть с петлями и менее очевидным направлением к выходу',
             edges=weave, gapx=0, gapy=0, exit=(12,0), barns=barns_c,
             keys=[(4,6),(12,11),(7,15)]),
    ]


class Canvas:
    def __init__(self):
        self.image = Image.new('RGB', (W,H), 'white')
        self.draw = ImageDraw.Draw(self.image)
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
                    '<rect width="100%" height="100%" fill="white"/>']

    def line(self, points, color=INK, width=7):
        pts = [(round(x),round(y)) for x,y in points]
        self.draw.line(pts, fill=color, width=width, joint='curve')
        radius = width/2
        for x,y in pts:
            self.draw.ellipse((x-radius,y-radius,x+radius,y+radius), fill=color)
        s = ' '.join(f'{x:.2f},{y:.2f}' for x,y in points)
        self.svg.append(f'<polyline points="{s}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')

    def rect(self, box, fill='white', stroke=INK, width=2):
        x0,y0,x1,y1 = box
        self.draw.rectangle(box, fill=fill, outline=stroke, width=width)
        self.svg.append(f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')

    def circle(self, x,y,r,fill='white',stroke=INK,width=2):
        self.draw.ellipse((x-r,y-r,x+r,y+r),fill=fill,outline=stroke,width=width)
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')

    def text(self,x,y,value,size=24,color=INK,bold=False,anchor='lm'):
        font = ImageFont.truetype(BOLD if bold else REGULAR,size)
        self.draw.text((x,y),value,font=font,fill=color,anchor=anchor)
        alignment = 'middle' if anchor.startswith('m') else 'start'
        weight = '700' if bold else '400'
        self.svg.append(f'<text x="{x}" y="{y}" font-family="Arial, sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{alignment}" dominant-baseline="central">{html.escape(value)}</text>')


def render(config):
    c = Canvas()
    c.text(80,47,f'ВАРИАНТ {config["number"]}',22,BLUE,True)
    c.text(80,98,config['title'],39,bold=True)
    c.text(80,146,config['subtitle'],23,color='#5b626a')
    def xy(node):
        x,y = node
        return (150+x*(900-config['gapx'])/17+(config['gapx'] if x>=9 else 0),
                250+y*(900-config['gapy'])/17+(config['gapy'] if y>=9 else 0))
    # Thin light-gray perimeter is a field boundary, not a trail or wall.
    c.rect((126,226,1074,1174),stroke='#d9dde1',width=1)
    for a,b in sorted(config['edges']):
        c.line([xy(a),xy(b)],width=7)
    x,y = xy(config['exit'])
    c.line([(x,y),(x,211)],width=8)
    c.rect((x-15,191,x+15,220),fill='white',stroke=INK,width=3)
    c.circle(x+7,207,2,fill=INK,width=1)
    c.text(x,177,'ФИНИШ',21,bold=True,anchor='mm')
    for number,node in enumerate(((0,0),(17,0),(0,17),(17,17)),1):
        sx,sy = xy(node)
        c.circle(sx,sy,22,fill=BLUE,stroke='white',width=3)
        c.text(sx,sy,str(number),25,color='white',bold=True,anchor='mm')
    for number,(a,b) in enumerate(config['barns'],1):
        ax,ay = xy(a); bx,by = xy(b)
        mx,my = (ax+bx)/2,(ay+by)/2
        horizontal = a[1] == b[1]
        halfx,halfy = (24,18) if horizontal else (18,24)
        c.rect((mx-halfx,my-halfy,mx+halfx,my+halfy),fill='#fbf4e7',stroke=GOLD,width=2)
        if horizontal:
            c.line([(ax,ay),(bx,by)],width=7)
            c.text(mx,my-halfy-12,f'С{number}',18,GOLD,True,'mm')
        else:
            c.line([(ax,ay),(bx,by)],width=7)
            c.text(mx+halfx+7,my,f'С{number}',18,GOLD,True)
    for node in config['keys']:
        kx,ky = xy(node)
        c.circle(kx,ky,17,fill='white',stroke=GOLD,width=2)
        c.text(kx,ky,'К?',15,GOLD,True,'mm')
    c.line([(81,1222),(131,1222)],width=7)
    c.text(151,1222,'Дорожки',23)
    c.rect((345,1210,381,1234),stroke='#c5cbd1',width=1)
    c.text(398,1222,'Кукуруза',23)
    c.circle(615,1222,15,fill=BLUE,stroke=BLUE)
    c.text(615,1222,'1',17,'white',True,'mm')
    c.text(644,1222,'Старт игрока',23)
    c.rect((861,1208,895,1236),fill='#fbf4e7',stroke=GOLD,width=2)
    c.text(908,1222,'Сарай',23)
    c.text(80,1273,'К? — примеры мест поиска ключа; положение ещё не закреплено.',22,color=GOLD)
    c.text(80,1318,'Кукуруза проходима. Дверь открывается общим ключом.',23)
    c.text(80,1361,'Черновой вид сверху · без масштаба · схема ещё не выбрана',20,color='#69717a')
    stem = f'maze-layout-{config["number"]:02d}'
    c.image.save(OUT/f'{stem}.png')
    (OUT/f'{stem}.svg').write_text('\n'.join(c.svg+['</svg>']),encoding='utf-8')
    return c.image


def main():
    configs = configurations()
    manifest = []
    images = []
    for config in configs:
        adjacency = {node:set() for node in ((x,y) for x in range(N) for y in range(N))}
        for a,b in config['edges']:
            adjacency[a].add(b); adjacency[b].add(a)
        queue = deque([(0,0)]); seen = {(0,0)}
        while queue:
            for node in adjacency[queue.popleft()]-seen:
                seen.add(node); queue.append(node)
        assert len(seen) == N*N and all(p in seen for p in config['keys']+[config['exit']])
        assert all(barn in config['edges'] for barn in config['barns'])
        images.append(render(config))
        manifest.append({k:(sorted(v) if isinstance(v,set) else v) for k,v in config.items()}
                        | {'connected_nodes':len(seen),'black_is_trail':True,'white_is_corn':True,
                           'loops':len(config['edges'])-N*N+1})
    board = Image.new('RGB',(W*3,H),'white')
    for index,image in enumerate(images):
        board.paste(image,(index*W,0))
    board.save(OUT/'maze-layouts-comparison.png')
    (OUT/'layouts.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'output':str(OUT),'variants':len(images),
                      'connected_nodes_each':N*N,'scene_changes':False},ensure_ascii=False))


if __name__ == '__main__':
    main()
