(Older controller post: imperial units, incremental positioning for the step-over pass)
G20 G17
G54
S8000 M3
G90
G0 X0 Y0 Z0.5
G1 Z-0.05 F10
G91
G1 X1 Y0 F20
G1 X0 Y1
G1 X-1 Y0
G1 X0 Y-1
G90
G0 Z0.5
M5
M30
