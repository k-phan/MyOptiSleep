#ifndef __init_heat_source_c__
#define __init_heat_source_c__

void init_heat_source(float *b, 
					float khai_temp, 
					float outside_temp, 
					float heater_temp,
					float wall_temp,
					float window1,
					float window2,
					int length)
{
	int i,j;
	
	/********************
		 heat sources
	*********************/
	/* window */
	for(j = 64; j < 192; j++)		// x = [4, 12), y = 0
	{
		for(i = 0; i < 16; i++) {
			b[i*length + j] = window1*(outside_temp) + (1-window1)*(heater_temp);
		}
	}
	for(j = 320; j < 448; j++)		// x = [20, 28), y = 0
	{
		for(i = 0; i < 16; i++) {
			b[i*length + j] = window2*(outside_temp) + (1-window2)*(heater_temp);
		}
	}

	/* heater */
	for(j = 448; j < 496; j++)		// x = [28, 31)
	{
		for(i = 32; i < 176; i++)	// y = [2, 11)
		{
			b[i*length+j] = heater_temp;
		}
	}

	/* khais body */
	for(j = 32; j < 256; j++)		// x = [2, 16)
	{
		for(i = 32; i < 64; i++)	// y = [2, 4)
		{
			b[i*length+j] = khai_temp;
		}
	}

	/********************
		 heat sinks
	*********************/
	// left and right side wall
	for(i = 0; i < 512; i++)				// y = all
	{
		for(j = 0; j < 16; j++)				// x = 0
			b[i*length + j] = wall_temp;
		for(j = 496; j < 512; j++)			// x = 31
			b[i*length + j] = wall_temp;
	}
	//top side wall
	for(j = 0; j < 64; j++)					// x = [0, 4) 
	{
		for(i = 0; i < 16; i++)				// y = [0, 1)
			b[i*length + j] = wall_temp;
	}
	for(j = 192; j < 320; j++)				// x = [12, 20)
	{
		for(i = 0; i < 16; i++)				// y = [0, 1)
			b[i*length + j] = wall_temp;
	}
	for(j = 448; j < 512; j++)				// x = [28, 31]
	{
		for(i = 0; i < 16; i++)				// y = [0, 1)
			b[i*length + j] = wall_temp;
	}
	//bottom wall
	for(j = 0; j < 512; j++)				// y = 31
	{
		for(i = 496; i < 512; i++)			// x = all
			b[i*length + j] = wall_temp;
	}
}

#endif
