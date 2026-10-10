(Large facing pass that would exceed a 300x180x80mm hobby machine's travel)
(Included to positive-control-test the opt-in machine envelope check)
G90 G21 G17
G54
S6000 M3
G0 X0 Y0 Z10
G0 Z2
G1 Z-1 F300
G1 X350 Y0 F800
G1 X350 Y200
G1 X0 Y200
G1 X0 Y0
G0 Z10
M5
M30
