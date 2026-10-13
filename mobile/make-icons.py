# -*- coding: utf-8 -*-
"""Iconos y pantalla de carga de la app de Android a partir de los del juego.

    python3 mobile/make-icons.py

- Icono adaptativo (Android 8+): el icono "maskable" (fondo oscuro a sangre y
  la Poké Ball dentro de la zona segura) como capa de delante, y el mismo azul
  oscuro de fondo.
- Icono clásico y redondo para launchers antiguos.
- Pantalla de carga: el azul oscuro del juego con la Poké Ball en el centro.
Todo se escala con vecino más próximo para que el pixel art siga nítido.
Necesita Pillow.
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
RES = os.path.join(HERE, 'android', 'app', 'src', 'main', 'res')
ICON = Image.open(os.path.join(ROOT, 'assets', 'icons', 'icon-512.png')).convert('RGBA')
MASK = Image.open(os.path.join(ROOT, 'assets', 'icons', 'icon-maskable-512.png')).convert('RGBA')
BG = MASK.getpixel((4, 4))[:3]

DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def px(img, size):
    return img.resize((size, size), Image.NEAREST)


def save(img, *parts):
    path = os.path.join(RES, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


for d, k in DENS.items():
    legacy = round(48 * k)
    save(px(ICON, legacy), 'mipmap-' + d, 'ic_launcher.png')
    rnd = px(MASK, legacy)
    m = Image.new('L', rnd.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, legacy - 1, legacy - 1), fill=255)
    rnd.putalpha(m)
    save(rnd, 'mipmap-' + d, 'ic_launcher_round.png')
    save(px(MASK, round(108 * k)), 'mipmap-' + d, 'ic_launcher_foreground.png')

with open(os.path.join(RES, 'values', 'ic_launcher_background.xml'), 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#%02x%02x%02x</color>\n</resources>\n' % BG)

# Pantalla de carga: mismo tamaño que la que trae Capacitor en cada carpeta.
for dirpath, _, files in os.walk(RES):
    if 'splash.png' in files:
        p = os.path.join(dirpath, 'splash.png')
        w, h = Image.open(p).size
        out = Image.new('RGB', (w, h), BG)
        s = (min(w, h) * 2 // 5) // 32 * 32 or 64
        ball = px(MASK, s)
        out.paste(ball, ((w - s) // 2, (h - s) // 2), ball)
        out.save(p)
print('ok, fondo #%02x%02x%02x' % BG)
