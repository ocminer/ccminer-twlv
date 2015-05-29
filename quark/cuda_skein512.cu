#include <stdio.h>
#include <stdint.h>
#include <memory.h>

#include "cuda_helper.h"
#define TPB 128 
#define TPBf 128

// Take a look at: https://www.schneier.com/skein1.3.pdf

#define SHL(x, n)			((x) << (n))
#define SHR(x, n)			((x) >> (n))

static uint32_t *d_nonce[MAX_GPUS];

/*
 * M9_ ## s ## _ ## i  evaluates to s+i mod 9 (0 <= s <= 18, 0 <= i <= 7).
 */

#define M9_0_0    0
#define M9_0_1    1
#define M9_0_2    2
#define M9_0_3    3
#define M9_0_4    4
#define M9_0_5    5
#define M9_0_6    6
#define M9_0_7    7

#define M9_1_0    1
#define M9_1_1    2
#define M9_1_2    3
#define M9_1_3    4
#define M9_1_4    5
#define M9_1_5    6
#define M9_1_6    7
#define M9_1_7    8

#define M9_2_0    2
#define M9_2_1    3
#define M9_2_2    4
#define M9_2_3    5
#define M9_2_4    6
#define M9_2_5    7
#define M9_2_6    8
#define M9_2_7    0

#define M9_3_0    3
#define M9_3_1    4
#define M9_3_2    5
#define M9_3_3    6
#define M9_3_4    7
#define M9_3_5    8
#define M9_3_6    0
#define M9_3_7    1

#define M9_4_0    4
#define M9_4_1    5
#define M9_4_2    6
#define M9_4_3    7
#define M9_4_4    8
#define M9_4_5    0
#define M9_4_6    1
#define M9_4_7    2

#define M9_5_0    5
#define M9_5_1    6
#define M9_5_2    7
#define M9_5_3    8
#define M9_5_4    0
#define M9_5_5    1
#define M9_5_6    2
#define M9_5_7    3

#define M9_6_0    6
#define M9_6_1    7
#define M9_6_2    8
#define M9_6_3    0
#define M9_6_4    1
#define M9_6_5    2
#define M9_6_6    3
#define M9_6_7    4

#define M9_7_0    7
#define M9_7_1    8
#define M9_7_2    0
#define M9_7_3    1
#define M9_7_4    2
#define M9_7_5    3
#define M9_7_6    4
#define M9_7_7    5

#define M9_8_0    8
#define M9_8_1    0
#define M9_8_2    1
#define M9_8_3    2
#define M9_8_4    3
#define M9_8_5    4
#define M9_8_6    5
#define M9_8_7    6

#define M9_9_0    0
#define M9_9_1    1
#define M9_9_2    2
#define M9_9_3    3
#define M9_9_4    4
#define M9_9_5    5
#define M9_9_6    6
#define M9_9_7    7

#define M9_10_0   1
#define M9_10_1   2
#define M9_10_2   3
#define M9_10_3   4
#define M9_10_4   5
#define M9_10_5   6
#define M9_10_6   7
#define M9_10_7   8

#define M9_11_0   2
#define M9_11_1   3
#define M9_11_2   4
#define M9_11_3   5
#define M9_11_4   6
#define M9_11_5   7
#define M9_11_6   8
#define M9_11_7   0

#define M9_12_0   3
#define M9_12_1   4
#define M9_12_2   5
#define M9_12_3   6
#define M9_12_4   7
#define M9_12_5   8
#define M9_12_6   0
#define M9_12_7   1

#define M9_13_0   4
#define M9_13_1   5
#define M9_13_2   6
#define M9_13_3   7
#define M9_13_4   8
#define M9_13_5   0
#define M9_13_6   1
#define M9_13_7   2

#define M9_14_0   5
#define M9_14_1   6
#define M9_14_2   7
#define M9_14_3   8
#define M9_14_4   0
#define M9_14_5   1
#define M9_14_6   2
#define M9_14_7   3

#define M9_15_0   6
#define M9_15_1   7
#define M9_15_2   8
#define M9_15_3   0
#define M9_15_4   1
#define M9_15_5   2
#define M9_15_6   3
#define M9_15_7   4

#define M9_16_0   7
#define M9_16_1   8
#define M9_16_2   0
#define M9_16_3   1
#define M9_16_4   2
#define M9_16_5   3
#define M9_16_6   4
#define M9_16_7   5

#define M9_17_0   8
#define M9_17_1   0
#define M9_17_2   1
#define M9_17_3   2
#define M9_17_4   3
#define M9_17_5   4
#define M9_17_6   5
#define M9_17_7   6

#define M9_18_0   0
#define M9_18_1   1
#define M9_18_2   2
#define M9_18_3   3
#define M9_18_4   4
#define M9_18_5   5
#define M9_18_6   6
#define M9_18_7   7

/*
 * M3_ ## s ## _ ## i  evaluates to s+i mod 3 (0 <= s <= 18, 0 <= i <= 1).
 */

#define M3_0_0    0
#define M3_0_1    1
#define M3_1_0    1
#define M3_1_1    2
#define M3_2_0    2
#define M3_2_1    0
#define M3_3_0    0
#define M3_3_1    1
#define M3_4_0    1
#define M3_4_1    2
#define M3_5_0    2
#define M3_5_1    0
#define M3_6_0    0
#define M3_6_1    1
#define M3_7_0    1
#define M3_7_1    2
#define M3_8_0    2
#define M3_8_1    0
#define M3_9_0    0
#define M3_9_1    1
#define M3_10_0   1
#define M3_10_1   2
#define M3_11_0   2
#define M3_11_1   0
#define M3_12_0   0
#define M3_12_1   1
#define M3_13_0   1
#define M3_13_1   2
#define M3_14_0   2
#define M3_14_1   0
#define M3_15_0   0
#define M3_15_1   1
#define M3_16_0   1
#define M3_16_1   2
#define M3_17_0   2
#define M3_17_1   0
#define M3_18_0   0
#define M3_18_1   1

#define XCAT(x, y)     XCAT_(x, y)
#define XCAT_(x, y)    x ## y

#define SKBI(k, s, i)   XCAT(k, XCAT(XCAT(XCAT(M9_, s), _), i))
#define SKBT(t, s, v)   XCAT(t, XCAT(XCAT(XCAT(M3_, s), _), v))

#define TFBIG_KINIT(k0, k1, k2, k3, k4, k5, k6, k7, k8, t0, t1, t2) { \
		k8 = ((k0 ^ k1) ^ (k2 ^ k3)) ^ ((k4 ^ k5) ^ (k6 ^ k7)) \
			^ make_uint2( 0xA9FC1A22UL,0x1BD11BDA); \
		t2 = t0 ^ t1; \
	}
//vectorize(0x1BD11BDAA9FC1A22ULL);
#define TFBIG_ADDKEY(w0, w1, w2, w3, w4, w5, w6, w7, k, t, s) { \
		w0 = (w0 + SKBI(k, s, 0)); \
		w1 = (w1 + SKBI(k, s, 1)); \
		w2 = (w2 + SKBI(k, s, 2)); \
		w3 = (w3 + SKBI(k, s, 3)); \
		w4 = (w4 + SKBI(k, s, 4)); \
		w5 = (w5 + SKBI(k, s, 5) + SKBT(t, s, 0)); \
		w6 = (w6 + SKBI(k, s, 6) + SKBT(t, s, 1)); \
		w7 = (w7 + SKBI(k, s, 7) + vectorizelow(s)); \
	}

#define TFBIG_MIX(x0, x1, rc) { \
		x0 = x0 + x1; \
		x1 = ROL2(x1, rc) ^ x0; \
	}

#define TFBIG_MIX8(w0, w1, w2, w3, w4, w5, w6, w7, rc0, rc1, rc2, rc3) { \
		TFBIG_MIX(w0, w1, rc0); \
		TFBIG_MIX(w2, w3, rc1); \
		TFBIG_MIX(w4, w5, rc2); \
		TFBIG_MIX(w6, w7, rc3); \
	}

#define TFBIG_4e(s)  { \
		TFBIG_ADDKEY(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], h, t, s); \
		TFBIG_MIX8(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], 46, 36, 19, 37); \
		TFBIG_MIX8(p[2], p[1], p[4], p[7], p[6], p[5], p[0], p[3], 33, 27, 14, 42); \
		TFBIG_MIX8(p[4], p[1], p[6], p[3], p[0], p[5], p[2], p[7], 17, 49, 36, 39); \
		TFBIG_MIX8(p[6], p[1], p[0], p[7], p[2], p[5], p[4], p[3], 44,  9, 54, 56); \
	}

#define TFBIG_4o(s)  { \
		TFBIG_ADDKEY(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], h, t, s); \
		TFBIG_MIX8(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], 39, 30, 34, 24); \
		TFBIG_MIX8(p[2], p[1], p[4], p[7], p[6], p[5], p[0], p[3], 13, 50, 10, 17); \
		TFBIG_MIX8(p[4], p[1], p[6], p[3], p[0], p[5], p[2], p[7], 25, 29, 39, 43); \
		TFBIG_MIX8(p[6], p[1], p[0], p[7], p[2], p[5], p[4], p[3],  8, 35, 56, 22); \
	}

__global__
#if __CUDA_ARCH__ > 500
__launch_bounds__(TPB, 2)
#else
__launch_bounds__(TPB, 1)
#endif
void quark_skein512_gpu_hash_64(uint32_t threads, uint32_t startNounce, uint64_t * const __restrict__ g_hash, uint32_t *g_nonceVector)
{
	uint32_t thread = (blockDim.x * blockIdx.x + threadIdx.x);
	if (thread < threads)
	{
		// Skein
		uint2 p[8];
		uint2 h0, h1, h2, h3, h4, h5, h6, h7, h8;
		uint2 t0, t1, t2;

		uint32_t nounce = (g_nonceVector != NULL) ? g_nonceVector[thread] : (startNounce + thread);

		int hashPosition = nounce - startNounce;
		uint64_t *inpHash = &g_hash[8 * hashPosition];

		h0 = make_uint2(0x749C51CEull, 0x4903ADFF);
		h1 = make_uint2(0x9746DF03ull, 0x0D95DE39);
		h2 = make_uint2(0x27C79BCEull, 0x8FD19341);
		h3 = make_uint2(0xFF352CB1ull, 0x9A255629);
		h4 = make_uint2(0xDF6CA7B0ull, 0x5DB62599);
		h5 = make_uint2(0xA9D5C3F4ull, 0xEABE394C);
		h6 = make_uint2(0x1A75B523ull, 0x991112C7);
		h7 = make_uint2(0x660FCC33ull, 0xAE18A40B);

		// 1. Runde -> etype = 480, ptr = 64, bcount = 0, data = msg		
#pragma unroll 8
		for(int i=0;i<8;i++)
			p[i] = vectorize(inpHash[i]);

		t0 = vectorizelow(64); // ptr
		t1 = vectorize(480ull << 55); // etype
		TFBIG_KINIT(h0, h1, h2, h3, h4, h5, h6, h7, h8, t0, t1, t2);
		TFBIG_4e(0);
		TFBIG_4o(1);
		TFBIG_4e(2);
		TFBIG_4o(3);
		TFBIG_4e(4);
		TFBIG_4o(5);
		TFBIG_4e(6);
		TFBIG_4o(7);
		TFBIG_4e(8);
		TFBIG_4o(9);
		TFBIG_4e(10);
		TFBIG_4o(11);
		TFBIG_4e(12);
		TFBIG_4o(13);
		TFBIG_4e(14);
		TFBIG_4o(15);
		TFBIG_4e(16);
		TFBIG_4o(17);
		TFBIG_ADDKEY(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], h, t, 18);

		h0 = vectorize(inpHash[0]) ^ p[0];
		h1 = vectorize(inpHash[1]) ^ p[1];
		h2 = vectorize(inpHash[2]) ^ p[2];
		h3 = vectorize(inpHash[3]) ^ p[3];
		h4 = vectorize(inpHash[4]) ^ p[4];
		h5 = vectorize(inpHash[5]) ^ p[5];
		h6 = vectorize(inpHash[6]) ^ p[6];
		h7 = vectorize(inpHash[7]) ^ p[7];

		// 2. Runde -> etype = 510, ptr = 8, bcount = 0, data = 0
#pragma unroll 8
		for(int i=0;i<8;i++)
			p[i] = make_uint2(0,0);

		t0 = vectorizelow(8); // ptr
		t1 = vectorize(510ull << 55); // etype
		TFBIG_KINIT(h0, h1, h2, h3, h4, h5, h6, h7, h8, t0, t1, t2);
		TFBIG_4e(0);
		TFBIG_4o(1);
		TFBIG_4e(2);
		TFBIG_4o(3);
		TFBIG_4e(4);
		TFBIG_4o(5);
		TFBIG_4e(6);
		TFBIG_4o(7);
		TFBIG_4e(8);
		TFBIG_4o(9);
		TFBIG_4e(10);
		TFBIG_4o(11);
		TFBIG_4e(12);
		TFBIG_4o(13);
		TFBIG_4e(14);
		TFBIG_4o(15);
		TFBIG_4e(16);
		TFBIG_4o(17);
		TFBIG_ADDKEY(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], h, t, 18);

		// fertig
		uint64_t *outpHash = &g_hash[8 * hashPosition];

#pragma unroll 8
		for(int i=0;i<8;i++)
			outpHash[i] = devectorize(p[i]);
	}
}

__global__ 
#if __CUDA_ARCH__ > 500
__launch_bounds__(TPBf, 2)
#else
__launch_bounds__(TPBf, 1)
#endif
void quark_skein512_gpu_hash_64_final(const uint32_t threads, const uint32_t startNounce, uint64_t * const __restrict__ g_hash, const uint32_t *g_nonceVector, uint32_t *d_nonce, uint32_t target)
{
	uint32_t thread = (blockDim.x * blockIdx.x + threadIdx.x);
	if (thread < threads)
	{
		// Skein
		uint2 p[8];
		uint2 h0, h1, h2, h3, h4, h5, h6, h7, h8;
		uint2 t0, t1, t2;

		uint32_t nounce = (g_nonceVector != NULL) ? g_nonceVector[thread] : (startNounce + thread);

		int hashPosition = nounce - startNounce;
		uint64_t *inpHash = &g_hash[8 * hashPosition];

		h0 = make_uint2(0x749C51CEull, 0x4903ADFF);
		h1 = make_uint2(0x9746DF03ull, 0x0D95DE39);
		h2 = make_uint2(0x27C79BCEull, 0x8FD19341);
		h3 = make_uint2(0xFF352CB1ull, 0x9A255629);
		h4 = make_uint2(0xDF6CA7B0ull, 0x5DB62599);
		h5 = make_uint2(0xA9D5C3F4ull, 0xEABE394C);
		h6 = make_uint2(0x1A75B523ull, 0x991112C7);
		h7 = make_uint2(0x660FCC33ull, 0xAE18A40B);

		// 1. Runde -> etype = 480, ptr = 64, bcount = 0, data = msg		
#pragma unroll 8
		for (int i = 0; i<8; i++)
			p[i] = vectorize(inpHash[i]);

		t0 = vectorizelow(64); // ptr
		t1 = vectorize(480ull << 55); // etype
		TFBIG_KINIT(h0, h1, h2, h3, h4, h5, h6, h7, h8, t0, t1, t2);
		TFBIG_4e(0);
		TFBIG_4o(1);
		TFBIG_4e(2);
		TFBIG_4o(3);
		TFBIG_4e(4);
		TFBIG_4o(5);
		TFBIG_4e(6);
		TFBIG_4o(7);
		TFBIG_4e(8);
		TFBIG_4o(9);
		TFBIG_4e(10);
		TFBIG_4o(11);
		TFBIG_4e(12);
		TFBIG_4o(13);
		TFBIG_4e(14);
		TFBIG_4o(15);
		TFBIG_4e(16);
		TFBIG_4o(17);
		TFBIG_ADDKEY(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], h, t, 18);

		h0 = vectorize(inpHash[0]) ^ p[0];
		h1 = vectorize(inpHash[1]) ^ p[1];
		h2 = vectorize(inpHash[2]) ^ p[2];
		h3 = vectorize(inpHash[3]) ^ p[3];
		h4 = vectorize(inpHash[4]) ^ p[4];
		h5 = vectorize(inpHash[5]) ^ p[5];
		h6 = vectorize(inpHash[6]) ^ p[6];
		h7 = vectorize(inpHash[7]) ^ p[7];

		// 2. Runde -> etype = 510, ptr = 8, bcount = 0, data = 0
#pragma unroll 8
		for (int i = 0; i<8; i++)
			p[i] = make_uint2(0, 0);

		t0 = vectorizelow(8); // ptr
		t1 = vectorize(510ull << 55); // etype
		TFBIG_KINIT(h0, h1, h2, h3, h4, h5, h6, h7, h8, t0, t1, t2);
		TFBIG_4e(0);
		TFBIG_4o(1);
		TFBIG_4e(2);
		TFBIG_4o(3);
		TFBIG_4e(4);
		TFBIG_4o(5);
		TFBIG_4e(6);
		TFBIG_4o(7);
		TFBIG_4e(8);
		TFBIG_4o(9);
		TFBIG_4e(10);
		TFBIG_4o(11);
		TFBIG_4e(12);
		TFBIG_4o(13);
		TFBIG_4e(14);
		TFBIG_4o(15);
		TFBIG_4e(16);
		TFBIG_ADDKEY(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], h, t, 17); 
		p[0] = p[0] + p[1];
		p[1] = ROL2(p[1], 39) ^ p[0];
		p[2] = p[2] + p[3];
		p[3] = ROL2(p[3], 30) ^ p[2];
		p[4] = p[4] + p[5];
		p[5] = ROL2(p[5], 34) ^ p[4];
		p[6] = p[6] + p[7];
		p[7] = ROL2(p[7], 24) ^ p[6];
		p[1] = ROL2(p[1], 13) ^ (p[2] + p[1]);
		p[3] = ROL2(p[3], 17) ^ (p[0] + p[3]);
		p[3] = ROL2(p[3], 29) ^ (p[6] + p[5] + p[3]);
		p[3] = (ROL2(p[3], 22) ^ (p[4] + p[7] + p[1] + p[3])) + h3;

		if (p[3].y <= target)
		{
			uint32_t tmp = atomicExch(&d_nonce[0], nounce);
			if (tmp != 0xffffffff)
				d_nonce[1] = tmp;
		}
	}
}


__host__ void quark_skein512_cpu_init(int thr_id)
{
	cudaMalloc(&d_nonce[thr_id], 2*sizeof(uint32_t));
}

__host__ void quark_skein512_setTarget(const void *ptarget)
{
}
__host__ void quark_skein512_cpu_free(int32_t thr_id)
{
	cudaFreeHost(&d_nonce[thr_id]);
}

__host__
void quark_skein512_cpu_hash_64(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_nonceVector, uint32_t *d_hash, int order)
{
	// berechne wie viele Thread Blocks wir brauchen
	dim3 grid((threads + TPB-1)/TPB);
	dim3 block(TPB);

	quark_skein512_gpu_hash_64 << <grid, block>> >(threads, startNounce, (uint64_t*)d_hash, d_nonceVector);
//	MyStreamSynchronize(NULL, order, thr_id);
}


__host__
void quark_skein512_cpu_hash_64_final(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_nonceVector, uint32_t *d_hash, uint32_t *h_nonce, uint32_t target, int order)
{
	dim3 grid((threads + TPBf - 1) / TPBf);
	dim3 block(TPBf);

	cudaMemset(d_nonce[thr_id], 0xff, 2*sizeof(uint32_t));

	quark_skein512_gpu_hash_64_final<< <grid, block>> >(threads, startNounce, (uint64_t*)d_hash, d_nonceVector, d_nonce[thr_id], target);
	cudaMemcpy(h_nonce, d_nonce[thr_id], 2*sizeof(uint32_t), cudaMemcpyDeviceToHost);
}

