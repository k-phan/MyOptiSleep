set terminal pdf
set output "scale100.pdf"
set title '100,000 Iterations'
set xlabel 'Bottom Side Wall'
set ylabel 'Left Side Wall'
set view map
set dgrid3d
set pm3d interpolate 100,100
set xrange[0:512]
set yrange[0:512]
unset key
set palette defined (  0 "blue" , 3 "green", 6 "yellow", 9 "orange", 12 "red", 15"purple")
set cbrange [ 76 : 79 ]
splot "scale100.dat" using 2:1:3 with pm3d