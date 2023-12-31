#include <cmath>
#include <iostream>
#include "gpu-new-forward.h"

#define TILE_WIDTH 16
#define KERNEL_SIZE 7
#define NUM_KERNEL 64

__constant__ float kernel[KERNEL_SIZE*KERNEL_SIZE*NUM_KERNEL];

__global__ void conv_forward_kernel(float *y, const float *x, const int B, const int M, const int C, const int H, const int W, const int K)
{
    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.

    Function paramter definitions:
    y - output
    x - input
    k - kernel(W*)
    B - batch_size (number of images in x)(N)
    M - number of output feature maps
    C - number of input feature maps
    H - input height dimension
    W - input width dimension
    K - kernel height and width (K x K)
    */

    const int H_out = H - K + 1;
    const int W_out = H - K + 1;
    int W_grid = (W_out - 1)/TILE_WIDTH + 1; // number of horizontal tiles per output map
    int b, m, h, w, c, p, q;
    b = blockIdx.x;
    m = blockIdx.y;
    h = (blockIdx.z / W_grid)*blockDim.y + threadIdx.y;
    w = (blockIdx.z % W_grid)*blockDim.x + threadIdx.x;
    // We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    // An example use of these macros:
    // float a = y4d(0,0,0,0)
    // y4d(0,0,0,0) = a
    #define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
    #define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
    #define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]
    // Insert your GPU convolution kernel code here
    
    if(h < H_out && w < W_out){
        float acc = 0;
        for (c = 0; c < C; c++) { // sum over all input channels
            for (p = 0; p < K; p++){ // loop over KxK filter
                for (q = 0; q < K; q++)
                    acc += x4d(b, c, h + p, w + q) * k4d(m, c, p, q);
            }
        }
        y4d(b, m, h, w) = acc;
    }
   

#undef y4d
#undef x4d
#undef k4d
}

	
__host__ void GPUInterface::conv_forward_gpu_prolog(const float *host_y, const float *host_x, const float *host_k, float **device_y_ptr, float **device_x_ptr, float **device_k_ptr, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Allocate memory and copy over the relevant data structures to the GPU
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    int W_grid = ceil(1.0*W_out/TILE_WIDTH); // number of horizontal tiles per output map
    int H_grid = ceil(1.0*H_out/TILE_WIDTH); // number of vertical tiles per output map
    int y_size = M*B*W_out*H_out;
    int x_size = C*B*H*W;
    int k_size = M*C*K*K;
    // We pass double pointers for you to initialize the relevant device pointers,
    //  which are passed to the other two functions.
    cudaMalloc((void **) device_x_ptr, x_size * sizeof(float));
    cudaMalloc((void **) device_y_ptr, y_size * sizeof(float));
    //cudaMalloc((void **) device_k_ptr, k_size * sizeof(float));

    cudaMemcpy(*device_x_ptr, host_x, x_size * sizeof(float), cudaMemcpyHostToDevice);
    //cudaMemcpy(*device_y_ptr, host_y, H * W * sizeof(float), cudaMemcpyHostToDevice)
    //cudaMemcpyToSymbol(kernel, host_k, NUM_KERNEL * KERNEL_SIZE * KERNEL_SIZE * sizeof(float), 0, cudaMemcpyHostToDevice); 

    cudaMemcpy(*device_k_ptr, host_k, k_size * sizeof(float), cudaMemcpyHostToDevice);
    // Useful snippet for error checking
    // cudaError_t error = cudaGetLastError();
    // if(error != cudaSuccess)
    // {
    //     std::cout<<"CUDA error: "<<cudaGetErrorString(error)<<std::endl;
    //     exit(-1);
    // }

}


__host__ void GPUInterface::conv_forward_gpu(float *device_y, const float *device_x, const float *device_k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Set the kernel dimensions and call the kernel
    





    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    int W_grid = ceil(1.0*W_out/TILE_WIDTH); // number of horizontal tiles per output map
    int H_grid = ceil(1.0*H_out/TILE_WIDTH); // number of vertical tiles per output map
    int Z = H_grid * W_grid;
    dim3 blockDim(TILE_WIDTH, TILE_WIDTH, 1);
    dim3 gridDim(B, M, Z);
    std::cout << "Kernel size" << K << std::endl;
    std::cout << "Input Height" << H << std::endl;
    std::cout << "Input Width" << W << std::endl;
    std::cout << "B" << B << std::endl;
    std::cout << "M" << M << std::endl;
    std::cout << "C" << C << std::endl;
    conv_forward_kernel<<< gridDim, blockDim>>>(device_y, device_x, B, M, C, H, W, K);
    cudaDeviceSynchronize();
}


__host__ void GPUInterface::conv_forward_gpu_epilog(float *host_y, float *device_y, float *device_x, float *device_k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Copy the output back to host
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    int y_size = M*B*W_out*H_out;
    //cudaMemcpy(*device_x_ptr, host_x, H * W * sizeof(float), cudaMemcpyHostToDevice
    cudaMemcpy(host_y, device_y, y_size * sizeof(float), cudaMemcpyDeviceToHost);
    //cudaMemcpy(*device_k_ptr, host_k, K * K * sizeof(float), cudaMemcpyHostToDevice)

    // Free device memory
    cudaFree(device_y);
    cudaFree(device_x);
    cudaFree(device_k);

}


__host__ void GPUInterface::get_device_properties()
{
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);

    for(int dev = 0; dev < deviceCount; dev++)
    {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, dev);

        std::cout<<"Device "<<dev<<" name: "<<deviceProp.name<<std::endl;
        std::cout<<"Computational capabilities: "<<deviceProp.major<<"."<<deviceProp.minor<<std::endl;
        std::cout<<"Max Global memory size: "<<deviceProp.totalGlobalMem<<std::endl;
        std::cout<<"Max Constant memory size: "<<deviceProp.totalConstMem<<std::endl;
        std::cout<<"Max Shared memory size per block: "<<deviceProp.sharedMemPerBlock<<std::endl;
        std::cout<<"Max threads per block: "<<deviceProp.maxThreadsPerBlock<<std::endl;
        std::cout<<"Max block dimensions: "<<deviceProp.maxThreadsDim[0]<<" x, "<<deviceProp.maxThreadsDim[1]<<" y, "<<deviceProp.maxThreadsDim[2]<<" z"<<std::endl;
        std::cout<<"Max grid dimensions: "<<deviceProp.maxGridSize[0]<<" x, "<<deviceProp.maxGridSize[1]<<" y, "<<deviceProp.maxGridSize[2]<<" z"<<std::endl;
        std::cout<<"Warp Size: "<<deviceProp.warpSize<<std::endl;
    }
}
