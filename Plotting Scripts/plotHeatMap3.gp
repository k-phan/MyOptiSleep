set terminal pdf
set output "scale3.pdf"
set view map
set dgrid3d
set pm3d interpolate 100,100
set xrange[0:512]
set yrange[0:512]
splot "scale3.dat" using 1:2:3 with pm3d