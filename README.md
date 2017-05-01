# OptiSleep

### Run Instructions
```
ssh scc1.bu.edu
scp file to scc1
qrsh -l gpus=1
module load cuda
# for preliminary check of all window combinations
nvcc Prelim_Optisleep.cu init_heat_source.c -o Prelim_Optisleep
./Prelim_Optisleep

# for big data on modeling the choice window params (0.8 and 0.5)
nvcc ModelOptisleep.cu init_heat_source.c -o ModelOptisleep
./ModelOptisleep
```
