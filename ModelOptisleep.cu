#include <cstdio>
#include <cstdlib>
#include <math.h>
#include <time.h>
#include "init_heat_source.c"

#define GIG 1000000000
#define CPG 2.0
// Assertion to check for errors
#define CUDA_SAFE_CALL(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, char *file, int line, bool abort=true)
{
	if (code != cudaSuccess) 
	{
		fprintf(stderr,"CUDA_SAFE_CALL: %s %s %d\n", cudaGetErrorString(code), file, line);
		if (abort) exit(code);
	}
}

#define NUM_THREADS_PER_BLOCK 	256
#define NUM_BLOCKS 				1024
#define PRINT_TIME 				0
#define SM_ARR_LEN				512
#define TOL						1

#define V_PRINT					0
#define CPU_VALIDATE			0

#define RHO 					0.1
#define ITERS 					1000

#define DRIFT					0.4

#define HEATER_TEMP				85
#define KHAI_TEMP 				98
#define OUTSIDE_TEMP			20
#define WALL_TEMP 				60
#define ROOM_TEMP				50


#define IMUL(a, b) __mul24(a, b)

void initializeArray1D(float *arr, int len, int size, float window1, float window2);

// y is starting point, result is finishing
// each kernel iteration is actually 2 relaxation calls
__global__ void kernel_sor_2d (int arrLen, int arrSize, float* x, float* y, float* result, float w_drift) {
	const int tid = IMUL(blockDim.x, blockIdx.x) + threadIdx.x;
	const int threadN = IMUL(blockDim.x, gridDim.x);
	
	__shared__ float mw_drift;
	mw_drift = ((1.0-w_drift)/3.0);

	int i;
	__shared__ int ignoreFlag[256];

	/* Walls & Heater */
	for(i = 0; i < 256; i++)
	if ((blockIdx.y == 0 || blockIdx.y == 31) || (blockIdx.x == 0 || blockIdx.x == 31) ||
		((blockIdx.x >= 28 && blockIdx.x < 31) && (blockIdx.y >= 2 && blockIdx.y < 11)))
		ignoreFlag[i] = 1;
	else
		ignoreFlag[i] = 0;

	/* Relax Here, Get Result from y, Get y from Result */
	for(i = tid; i < arrSize; i += threadN) {
		
		__syncthreads();
		if (ignoreFlag[tid%256]) {
			result[i] = RHO * y[i] + (1.0-RHO) * (
					w_drift *(y[((((i+arrLen)%arrSize))+arrSize)%arrSize]) +	//top    
					mw_drift*((y[(((i+1)%arrSize)+arrSize)%arrSize]) + 			//right  
							(y[(((i-1)%arrSize)+arrSize)%arrSize]) + 			//left
							(y[((((i-arrLen)%arrSize))+arrSize)%arrSize]))		//bottom
			);
		}
		else {
			result[i] = y[i];
		}

		__syncthreads();
		if (ignoreFlag[tid%256]) {
			y[i] = RHO * result[i] + (1.0-RHO) * (
					w_drift *(result[((((i+arrLen)%arrSize))+arrSize)%arrSize]) +	//top  	 
					mw_drift*((result[(((i+1)%arrSize)+arrSize)%arrSize]) + 		//right  
							(result[(((i-1)%arrSize)+arrSize)%arrSize]) + 			//left
							(result[((((i-arrLen)%arrSize))+arrSize)%arrSize])) 	//bottom
			);
		}
		else 
		{
			y[i] = result[i];	
		}

		__syncthreads();
		x[i] = y[i] - result[i];	// get residual array
	}
	__syncthreads();
}

int main(int argc, char **argv){
	int arrLen = 0;
	int arrSize = 0;
	int iterCount = 0;
	float w_drift;

	// GPU Timing variables
	cudaEvent_t start, stop;
	float elapsed_gpu;
	float total_time = 0;
	
	// Arrays on GPU global memoryc
	float *d_x;
	float *d_y;
	float *d_result;

	// Arrays on the host memory
	float *h_x;
	float *h_y;
	float *h_result;
	float *h_result_gold;

	// CPU Timers
	timespec time1, time2, elapsed_cpu;
	timespec diff(struct timespec start, struct timespec end);
	
	int i, errCount = 0, zeroCount = 0;
	float window1, window2;
	
	if (argc > 1) {
		arrLen  = atoi(argv[1]);
	}
	else {
		arrLen = SM_ARR_LEN;
	}

	arrSize = arrLen*arrLen;

	//printf("Length of the array = %d\n", arrLen);

    // Select GPU
    CUDA_SAFE_CALL(cudaSetDevice(0));

	// Allocate GPU memory
	size_t allocSize = arrSize * sizeof(float);
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_x, allocSize));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_y, allocSize));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_result, allocSize));
		
	// Allocate arrays on host memory
	h_x                        = (float *) malloc(allocSize);	// this is our error
	h_y                        = (float *) malloc(allocSize);	// this is our result every even
	h_result                   = (float *) malloc(allocSize);
	h_result_gold              = (float *) malloc(allocSize);

	int scale;
	float sumFaceTemp;
	float count;


	window1 = 0.8;
	window2 = 0.5;				
	count = 0.0;
	sumFaceTemp = 0.0;
	w_drift = .25 + 0.25 * (window1 + window2);

	// Initialize the host arrays
	//printf("\nInitializing the arrays ...");
	// Arrays are initialized with a known seed for reproducability
	initializeArray1D(h_x, arrLen, arrSize, window1, window2); //2453
	initializeArray1D(h_y, arrLen, arrSize, window1, window2); //1467
	//printf("\t... done\n\n");

	// int i, j;
	// for(i = 32; i < 128; i++)
	// {
	// 	for(j = 32; j < 64; j++)
	// 	{
	// 		sumFaceTemp += h_y[j*arrLen+i];
	// 		count += 1.0;
	// 		printf("Temperature at i: %d j: %d -- %.15f\n", i, j, h_y[i*arrLen + j]);
	// 	}
	// }
				
				
		#if PRINT_TIME
			// Create the cuda events
			cudaEventCreate(&start);
			cudaEventCreate(&stop);
			// Record event on the default stream
			cudaEventRecord(start, 0);
		#endif
					
				//printf("GPU work starting ...\n");
				// Transfer the arrays to the GPU memory
				//printf("GPU cudaMemcpyHostToDevice...\n");
				CUDA_SAFE_CALL(cudaMemcpy(d_x, h_x, allocSize, cudaMemcpyHostToDevice));
				CUDA_SAFE_CALL(cudaMemcpy(d_y, h_y, allocSize, cudaMemcpyHostToDevice));
				  
				// Launch the kernel
				//kernel_add<<<NUM_BLOCKS, NUM_THREADS_PER_BLOCK>>>(arrLen, d_x, d_y, d_result);
				//printf("GPU Kernel running...\n");

				////////////////////////
				// X IS NEVER USED /////
				////////////////////////
				// printf("%f\t%f\t%f\t",window1,window2,w_drift);
				int stopCount = 0;
				int loopFlag = 1;
				do {
					for (iterCount =0; iterCount < ITERS; iterCount++)
					{
						kernel_sor_2d<<<NUM_BLOCKS, NUM_THREADS_PER_BLOCK>>>(arrLen, arrSize, d_x, d_y, d_result, w_drift);
						CUDA_SAFE_CALL(cudaDeviceSynchronize());
					}		

					// Check for errors during launch
					//printf("GPU cudaPeekAtLastError\n");
					CUDA_SAFE_CALL(cudaPeekAtLastError());
					
					// Transfer the results back to the host
					//printf("GPU cudaMemcpyDeviceToHost\n");
					CUDA_SAFE_CALL(cudaMemcpy(h_y, d_y, allocSize, cudaMemcpyDeviceToHost));
					CUDA_SAFE_CALL(cudaMemcpy(h_x, d_x, allocSize, cudaMemcpyDeviceToHost));
					CUDA_SAFE_CALL(cudaDeviceSynchronize());

					stopCount++;
					if(stopCount == 3 || stopCount == 6 || stopCount == 12 || 
						stopCount == 25 || stopCount == 50 || stopCount == 100) {
						printf("scale=%d\n", stopCount);
						int cnti, cntj;
						for(cnti = 0; cnti < 512; cnti++) {
							for(cntj = 0; cntj < 512; cntj++) {
								printf("%d\t%d\t%f\n", cntj, cnti, h_y[cnti*arrLen + cntj]);
							}
						} 
					}
					
					if(stopCount == 100){
						loopFlag = 0;
					}

				}while(loopFlag);

		#if PRINT_TIME
			// Stop and destroy the timer
			cudaEventRecord(stop,0);
			cudaEventSynchronize(stop);
			cudaEventElapsedTime(&elapsed_gpu, start, stop);
			total_time = total_time + elapsed_gpu;
			//printf("\nGPU time: %f (msec)\n", elapsed_gpu);
			cudaEventDestroy(start);
			cudaEventDestroy(stop);
		#endif
			/******************
					ADD
					THIS
					BACK
					IN 
					LATER
					PLS

			******************/
				// if ((sumFaceTemp / count) > 68.00 && (sumFaceTemp / count) < 70.00) {
				// 	break;
				// }

#if PRINT_TIME
	printf("\n\nTotal Time: %f (msec)\n", total_time);
#endif
	

	
#if CPU_VALIDATE
	// Compute the results on the host
	/**/
	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time1);
	for(iterCount = 0; iterCount < ITERS/2; iterCount++){
		for(i = 0; i < arrSize; i++) {
			h_result_gold[i] = RHO * h_y[i]
				+ (0.25) * (1-RHO) * (	
					h_y[(((i+1)%arrSize)+arrSize)%arrSize] + h_y[((((i+arrLen)%arrSize))+arrSize)%arrSize] +
					h_y[(((i-1)%arrSize)+arrSize)%arrSize] + h_y[((((i-arrLen)%arrSize))+arrSize)%arrSize]
			);
		}

		for(i = 0; i < arrSize; i++) {
			h_y[i] = RHO * h_result_gold[i]
				+ (0.25) * (1-RHO) * (	
					h_result_gold[(((i+1)%arrSize)+arrSize)%arrSize] + h_result_gold[((((i+arrLen)%arrSize))+arrSize)%arrSize] +
					h_result_gold[(((i-1)%arrSize)+arrSize)%arrSize] + h_result_gold[((((i-arrLen)%arrSize))+arrSize)%arrSize]
			);
		}
	}
	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time2);

	elapsed_cpu = diff(time1, time2);
	long long int cputime = (long long int)((double)(CPG)*(double)(GIG * elapsed_cpu.tv_sec + elapsed_cpu.tv_nsec));
	printf("\nCPU time: %li (ns)\n", cputime);
	/**/


	/* Print the stuff */

	if (V_PRINT){
		printf("\n");
		for (i = 0; i < arrSize; i++)
		{
			printf("%.6f\t", h_x[i]);
			if (i%arrLen == arrLen-1)
				printf("\n");
		}
		
		printf("\n");
		for (i = 0; i < arrSize; i++)
		{
			printf("%.6f\t", h_result[i]);
			if (i%arrLen == arrLen-1)
				printf("\n");
		}
		/**/
		printf("\n");
		for (i = 0; i < arrSize; i++)
		{
			printf("%.6f\t", h_result_gold[i]);
			if (i%arrLen == arrLen-1)
				printf("\n");
		}
		/**/
	}

	/* --------------- */!

	// Compare the results
	/**/
	for(i = 0; i < arrSize; i++) {
		if (abs(h_result_gold[i] - h_result[i]) > TOL) {
			errCount++;
		}
		if (h_result[i] == 0) {
			zeroCount++;
		}
	}
	/**/

	/*
	for(i = 0; i < 50; i++) {
		printf("%d:\t%.8f\t%.8f\n", i, h_result_gold[i], h_result[i]);
	}
	*/

	/**/
	if ( V_PRINT && errCount > 0) {
		printf("\n@ERROR: TEST FAILED: %d results did not matched\n", errCount);
	}
	else if ( V_PRINT && zeroCount > 0){
		printf("\n@ERROR: TEST FAILED: %d results (from GPU) are zero\n", zeroCount);
	}
	else {
		printf("\nTEST PASSED: All results matched\n");
	}
	/**/
#endif

	//Free-up device and host memory
	CUDA_SAFE_CALL(cudaFree(d_x));
	CUDA_SAFE_CALL(cudaFree(d_y));
	CUDA_SAFE_CALL(cudaFree(d_result));
		   
	free(h_x);
	free(h_y);
	free(h_result);
		
	return 0;
}

void initializeArray1D(float *arr, int len, int size, float window1, float window2) {
	int i;

	for (i = 0; i < size; i++) {
		arr[i] = (float) 80;
	}

	init_heat_source(arr, KHAI_TEMP, OUTSIDE_TEMP, HEATER_TEMP, WALL_TEMP, window1, window2, len);

	//for(i = 0; i < size; i++) {
	//	printf("here i am temperature: %.15f\n", arr[i]);
	//}
}


struct timespec diff(struct timespec start, struct timespec end)
{
  struct timespec temp;
  if ((end.tv_nsec-start.tv_nsec)<0) {
    temp.tv_sec = end.tv_sec-start.tv_sec-1;
    temp.tv_nsec = 1000000000+end.tv_nsec-start.tv_nsec;
  } else {
    temp.tv_sec = end.tv_sec-start.tv_sec;
    temp.tv_nsec = end.tv_nsec-start.tv_nsec;
  }
  return temp;
}