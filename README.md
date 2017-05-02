# OptiSleep
### Room modeling
Modeling a room with an 85^o^ heater, two windows, and outside temperature at 20^o^.

How much should we open the windows to have the room tend to a comfortable temperature?


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
nvcc ModelOptisleep.cu init_heat_source.c -o Model_Optisleep
./Model_Optisleep

# for data on modeling the room with shift
nvcc Shift_Optisleep.cu init_heat_source.c -o Shift_Optisleep
./Shift_Optisleep
```
