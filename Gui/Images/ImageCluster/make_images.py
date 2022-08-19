from PIL import Image
import os
import math

BASE_DIR = os.getcwd().replace("\\", "/") + "/../../.."

HEALTH = BASE_DIR + "/Gui/Images/ImageCluster/Health/"
INK = BASE_DIR + "/Gui/Images/ImageCluster/Ink/"
COLORS = BASE_DIR + "/Gui/Images/ImageCluster/Colors/"

def RoundedImage(fixed_width, width, height, rounded_corners, color):
    image = Image.new( 'RGBA', (fixed_width, height), color)
    
    pixels = image.load()
    for z in range(fixed_width - width):
        for y in range(height):
            pixels[width+z, y] = (0, 0, 0, 0)

    if width > rounded_corners and height > rounded_corners:
        for i in range(rounded_corners):
            n = i
            val = max(min(round((rounded_corners - i) * 2.75), width), 0)
            # TOP LEFT
            for x in range(val):
                #print(x)
                pixels[x, n] = (0, 0, 0, 0)
            for y in range(val):
                pixels[n, y] = (0, 0, 0, 0)
            # TOP RIGHT
            for x in range(val):
                pixels[width-x-1, n] = (0, 0, 0, 0)
            for y in range(val):
                pixels[width-n-1, y] = (0, 0, 0, 0)
            # BOTTOM LEFT
            for x in range(val):
                pixels[x, height-n-1] = (0, 0, 0, 0)
            for y in range(val):
                pixels[n, height-y-1] = (0, 0, 0, 0)
            # BOTTOM RIGHT
            for x in range(val):
                pixels[width-x-1, height-n-1] = (0, 0, 0, 0)
            for y in range(val):
                pixels[width-n-1, height-y-1] = (0, 0, 0, 0)

    return image
"""
ZeroHp = Image.new( 'RGBA', (1, 1), "white")
ZeroHp.load()[0, 0] = (0,0,0,0)
ZeroHp.save(HEALTH + "health-image-0.png")

for health in range(100):
    RoundedImage(300, (health+1) * 3, 75, 5, "#ccf035").save(HEALTH + "health-image-"+str(health+1)+".png")

ZeroInk = Image.new( 'RGBA', (1, 1), "white")
ZeroInk.load()[0, 0] = (0,0,0,0)
ZeroInk.save(INK + "ink-image-0.png")

for ink in range(100):
    RoundedImage(300, (ink+1) * 3, 50, 5, "blue").save(INK + "ink-image-"+str(ink+1)+".png")
"""
# COLORS
color_array = []

# GET COLORS

COLOR_XML = BASE_DIR + "/Gui/Layouts/PaintGun.layout" # /Gui/Layouts

with open(COLOR_XML) as file_in:
    for line in file_in:
        if 'key="Colour" value="' in line:
            start = line.index('key="Colour" value="') + 21
            end = line[start:].index('"')
            color_array.append(line[start:start+end])

for color in color_array:
    height = 200
    width = 1000

    color_dir = COLORS + color + "/"
    if not os.path.exists(color_dir):
        os.makedirs(color_dir)

    invs_color = Image.new( 'RGBA', (1, 1), "white")
    invs_color.load()[0, 0] = (0,0,0,0)
    invs_color.save(color_dir + color + "-left-0.png")
    invs_color.save(color_dir + color + "-right-0.png")

    percentage = 100
    factor = int(width / percentage)

    for ink in range(percentage):
        IMG = RoundedImage(width, (ink+1) * factor, height, 5, "#" + color)
        IMG.save(color_dir + color + "-left-"+str(ink+1)+".png")
        IMG.transpose(Image.FLIP_LEFT_RIGHT).save(color_dir + color + "-right-"+str(ink+1)+".png")