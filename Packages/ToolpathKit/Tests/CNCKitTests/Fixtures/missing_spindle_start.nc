(Operator error: no M3/M4 anywhere in the program before cutting starts)
G90 G21 G17
G54
G0 X0 Y0 Z10
G0 Z2
G1 Z-1 F300
G1 X20 Y0 F500
G1 X20 Y20
G0 Z10
M30
