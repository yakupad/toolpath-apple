(Operator error: forgot to raise Z before rapid-traversing to next hole)
(This file intentionally reproduces a real mistake seen on the shop floor)
G90 G21 G17
G54
S10000 M3
G0 X0 Y0 Z10
G0 Z2
G1 Z-1 F300
G1 X10 Y0 F400
G0 Z10
G0 X40 Y0
(BUG: next line rapids straight down into stock instead of plunging with G1)
G0 X40 Y0 Z-1
G1 X50 Y0 F400
G0 Z10
M5
M30
