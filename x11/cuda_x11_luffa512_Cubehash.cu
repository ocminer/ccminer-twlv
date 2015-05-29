/*
 * luffa_for_32.c
 * Version 2.0 (Sep 15th 2009)
 *
 * Copyright (C) 2008-2009 Hitachi, Ltd. All rights reserved.
 *
 * Hitachi, Ltd. is the owner of this software and hereby grant
 * the U.S. Government and any interested party the right to use
 * this software for the purposes of the SHA-3 evaluation process,
 * notwithstanding that this software is copyrighted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include "cuda_helper.h"

typedef unsigned char BitSequence;

typedef struct {
    uint32_t buffer[8]; /* Buffer to be hashed */
    uint32_t chainv[40];   /* Chaining values */
} hashState;

#define MULT2(a,j)\
    tmp = a[7+(8*j)];\
    a[7+(8*j)] = a[6+(8*j)];\
    a[6+(8*j)] = a[5+(8*j)];\
    a[5+(8*j)] = a[4+(8*j)];\
    a[4+(8*j)] = a[3+(8*j)] ^ tmp;\
    a[3+(8*j)] = a[2+(8*j)] ^ tmp;\
    a[2+(8*j)] = a[1+(8*j)];\
    a[1+(8*j)] = a[0+(8*j)] ^ tmp;\
    a[0+(8*j)] = tmp;

#if __CUDA_ARCH__ < 350
#define LROT(x,bits) ((x << bits) | (x >> (32 - bits)))
#else
#define LROT(x, bits) __funnelshift_l(x, x, bits)
#endif

#define TWEAK(a0,a1,a2,a3,j)\
    a0 = LROT(a0,j);\
    a1 = LROT(a1,j);\
    a2 = LROT(a2,j);\
    a3 = LROT(a3,j);

#define STEP(c0,c1)\
    SUBCRUMB(chainv[0],chainv[1],chainv[2],chainv[3],tmp);\
    SUBCRUMB(chainv[5],chainv[6],chainv[7],chainv[4],tmp);\
    MIXWORD(chainv[0],chainv[4]);\
    MIXWORD(chainv[1],chainv[5]);\
    MIXWORD(chainv[2],chainv[6]);\
    MIXWORD(chainv[3],chainv[7]);\
    ADD_CONSTANT(chainv[0],chainv[4],c0,c1);

#define SUBCRUMB(a0,a1,a2,a3,a4)\
    a4  = a0;\
    a0 |= a1;\
    a2 ^= a3;\
    a1  = ~a1;\
    a0 ^= a3;\
    a3 &= a4;\
    a1 ^= a3;\
    a3 ^= a2;\
    a2 &= a0;\
    a0  = ~a0;\
    a2 ^= a1;\
    a1 |= a3;\
    a4 ^= a1;\
    a3 ^= a2;\
    a2 &= a1;\
    a1 ^= a0;\
    a0  = a4;

#define MIXWORD(a0,a4)\
    a4 ^= a0;\
    a0  = LROT(a0,2);\
    a0 ^= a4;\
    a4  = LROT(a4,14);\
    a4 ^= a0;\
    a0  = LROT(a0,10);\
    a0 ^= a4;\
    a4  = LROT(a4,1);

#define ADD_CONSTANT(a0,b0,c0,c1)\
    a0 ^= c0;\
    b0 ^= c1;

// Precalculated chaining values
__device__ __constant__ uint32_t c_IV[40] =
{ 0x8bb0a761, 0xc2e4aa8b, 0x2d539bc9, 0x381408f8,
0x478f6633, 0x255a46ff, 0x581c37f7, 0x601c2e8e,
0x266c5f9d, 0xc34715d8, 0x8900670e, 0x51a540be,
0xe4ce69fb, 0x5089f4d4, 0x3cc0a506, 0x609bcb02,
0xa4e3cd82, 0xd24fd6ca, 0xc0f196dc, 0xcf41eafe,
0x0ff2e673, 0x303804f2, 0xa7b3cd48, 0x677addd4,
0x66e66a8a, 0x2303208f, 0x486dafb4, 0xc0d37dc6,
0x634d15af, 0xe5af6747, 0x10af7e38, 0xee7e6428,
0x01262e5d, 0xc92c2e64, 0x82fee966, 0xcea738d3,
0x867de2b0, 0xe0714818, 0xda6e831f, 0xa7062529};



/* old chaining values
__device__ __constant__ uint32_t c_IV[40] = {
    0x6d251e69,0x44b051e0,0x4eaa6fb4,0xdbf78465,
    0x6e292011,0x90152df4,0xee058139,0xdef610bb,
    0xc3b44b95,0xd9d2f256,0x70eee9a0,0xde099fa3,
    0x5d9b0557,0x8fc944b3,0xcf1ccf0e,0x746cd581,
    0xf7efc89d,0x5dba5781,0x04016ce5,0xad659c05,
    0x0306194f,0x666d1836,0x24aa230a,0x8b264ae7,
    0x858075d5,0x36d79cce,0xe571f7d7,0x204b1f67,
    0x35870c6a,0x57e9e923,0x14bcb808,0x7cde72ce,
    0x6c68e9be,0x5ec41e22,0xc825b7c7,0xaffb4363,
    0xf5df3999,0x0fc688f1,0xb07224cc,0x03e86cea};
*/


__device__ __constant__ uint32_t c_CNS[80] = {
    0x303994a6,0xe0337818,0xc0e65299,0x441ba90d,
    0x6cc33a12,0x7f34d442,0xdc56983e,0x9389217f,
    0x1e00108f,0xe5a8bce6,0x7800423d,0x5274baf4,
    0x8f5b7882,0x26889ba7,0x96e1db12,0x9a226e9d,
    0xb6de10ed,0x01685f3d,0x70f47aae,0x05a17cf4,
    0x0707a3d4,0xbd09caca,0x1c1e8f51,0xf4272b28,
    0x707a3d45,0x144ae5cc,0xaeb28562,0xfaa7ae2b,
    0xbaca1589,0x2e48f1c1,0x40a46f3e,0xb923c704,
    0xfc20d9d2,0xe25e72c1,0x34552e25,0xe623bb72,
    0x7ad8818f,0x5c58a4a4,0x8438764a,0x1e38e2e7,
    0xbb6de032,0x78e38b9d,0xedb780c8,0x27586719,
    0xd9847356,0x36eda57f,0xa2c78434,0x703aace7,
    0xb213afa5,0xe028c9bf,0xc84ebe95,0x44756f91,
    0x4e608a22,0x7e8fce32,0x56d858fe,0x956548be,
    0x343b138f,0xfe191be2,0xd0ec4e3d,0x3cb226e5,
    0x2ceb4882,0x5944a28e,0xb3ad2208,0xa1c4c355,
    0xf0d2e9e3,0x5090d577,0xac11d7fa,0x2d1925ab,
    0x1bcb66f2,0xb46496ac,0x6f2d9bc9,0xd1925ab0,
    0x78602649,0x29131ab6,0x8edae952,0x0fc053c3,
    0x3b6ba548,0x3f014f0c,0xedae9520,0xfc053c31};


/***************************************************/
__device__ __forceinline__
void rnd512(hashState *state)
{
    int i,j;
    uint32_t t[40];
    uint32_t chainv[8];
    uint32_t tmp;

#pragma unroll 8
    for(i=0;i<8;i++) 
	{
		t[i] = 0;
#pragma unroll 5
        for(j=0;j<5;j++) 
		{
           t[i] ^= state->chainv[i+8*j];
        }
	}

    MULT2(t, 0);

#pragma unroll 5
    for(j=0;j<5;j++) {
#pragma unroll 8
        for(i=0;i<8;i++) {
            state->chainv[i+8*j] ^= t[i];
        }
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
#pragma unroll 8
        for(i=0;i<8;i++) {
            t[i+8*j] = state->chainv[i+8*j];
        }
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
        MULT2(state->chainv, j);
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
#pragma unroll 8
        for(i=0;i<8;i++) {
            state->chainv[8*j+i] ^= t[8*((j+1)%5)+i];
        }
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
#pragma unroll 8
        for(i=0;i<8;i++) {
            t[i+8*j] = state->chainv[i+8*j];
        }
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
        MULT2(state->chainv, j);
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
#pragma unroll 8
        for(i=0;i<8;i++) {
            state->chainv[8*j+i] ^= t[8*((j+4)%5)+i];
        }
    }

#pragma unroll 5
    for(j=0;j<5;j++) {
#pragma unroll 8
        for(i=0;i<8;i++) {
            state->chainv[i+8*j] ^= state->buffer[i];
        }
        MULT2(state->buffer, 0);
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        chainv[i] = state->chainv[i];
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        STEP(c_CNS[(2*i)],c_CNS[(2*i)+1]);
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        state->chainv[i] = chainv[i];
        chainv[i] = state->chainv[i+8];
    }

    TWEAK(chainv[4],chainv[5],chainv[6],chainv[7],1);

#pragma unroll 8
    for(i=0;i<8;i++) {
        STEP(c_CNS[(2*i)+16],c_CNS[(2*i)+16+1]);
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        state->chainv[i+8] = chainv[i];
        chainv[i] = state->chainv[i+16];
    }

    TWEAK(chainv[4],chainv[5],chainv[6],chainv[7],2);

#pragma unroll 8
    for(i=0;i<8;i++) {
        STEP(c_CNS[(2*i)+32],c_CNS[(2*i)+32+1]);
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        state->chainv[i+16] = chainv[i];
        chainv[i] = state->chainv[i+24];
    }

    TWEAK(chainv[4],chainv[5],chainv[6],chainv[7],3);

#pragma unroll 8
    for(i=0;i<8;i++) {
        STEP(c_CNS[(2*i)+48],c_CNS[(2*i)+48+1]);
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        state->chainv[i+24] = chainv[i];
        chainv[i] = state->chainv[i+32];
    }

    TWEAK(chainv[4],chainv[5],chainv[6],chainv[7],4);

#pragma unroll 8
    for(i=0;i<8;i++) {
        STEP(c_CNS[(2*i)+64],c_CNS[(2*i)+64+1]);
    }

#pragma unroll 8
    for(i=0;i<8;i++) {
        state->chainv[i+32] = chainv[i];
    }
}
__device__ __forceinline__
void rnd512_first(uint32_t state[40], uint32_t buffer[8])
{
	int i, j;
	uint32_t chainv[8];
	uint32_t tmp;

#pragma unroll 5
	for (j = 0; j<5; j++) {
		state[0 + 8 * j] ^= buffer[0];

#pragma unroll 7
		for (i = 1; i<8; i++) {
			state[i + 8 * j] ^= buffer[i];
		}
		MULT2(buffer, 0);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		chainv[i] = state[i];
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i)], c_CNS[(2 * i) + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i] = chainv[i];
		chainv[i] = state[i + 8];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 1);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 16], c_CNS[(2 * i) + 16 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 8] = chainv[i];
		chainv[i] = state[i + 16];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 2);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 32], c_CNS[(2 * i) + 32 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 16] = chainv[i];
		chainv[i] = state[i + 24];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 3);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 48], c_CNS[(2 * i) + 48 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 24] = chainv[i];
		chainv[i] = state[i + 32];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 4);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 64], c_CNS[(2 * i) + 64 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 32] = chainv[i];
	}
}

/***************************************************/
__device__ __forceinline__
void rnd512_nullhash(uint32_t *state)
{
	int i, j;
	uint32_t t[40];
	uint32_t chainv[8];
	uint32_t tmp;

#pragma unroll 8
	for (i = 0; i<8; i++) {
		t[i] = state[i + 8 * 0];
#pragma unroll 4
		for (j = 1; j<5; j++) {
			t[i] ^= state[i + 8 * j];
		}
	}

	MULT2(t, 0);

#pragma unroll 5
	for (j = 0; j<5; j++) {
#pragma unroll 8
		for (i = 0; i<8; i++) {
			state[i + 8 * j] ^= t[i];
		}
	}

#pragma unroll 5
	for (j = 0; j<5; j++) {
#pragma unroll 8
		for (i = 0; i<8; i++) {
			t[i + 8 * j] = state[i + 8 * j];
		}
	}

#pragma unroll 5
	for (j = 0; j<5; j++) {
		MULT2(state, j);
	}

#pragma unroll 5
	for (j = 0; j<5; j++) {
#pragma unroll 8
		for (i = 0; i<8; i++) {
			state[8 * j + i] ^= t[8 * ((j + 1) % 5) + i];
		}
	}

#pragma unroll 5
	for (j = 0; j<5; j++) {
#pragma unroll 8
		for (i = 0; i<8; i++) {
			t[i + 8 * j] = state[i + 8 * j];
		}
	}

#pragma unroll 5
	for (j = 0; j<5; j++) {
		MULT2(state, j);
	}

#pragma unroll 5
	for (j = 0; j<5; j++) {
#pragma unroll 8
		for (i = 0; i<8; i++) {
			state[8 * j + i] ^= t[8 * ((j + 4) % 5) + i];
		}
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		chainv[i] = state[i];
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i)], c_CNS[(2 * i) + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i] = chainv[i];
		chainv[i] = state[i + 8];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 1);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 16], c_CNS[(2 * i) + 16 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 8] = chainv[i];
		chainv[i] = state[i + 16];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 2);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 32], c_CNS[(2 * i) + 32 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 16] = chainv[i];
		chainv[i] = state[i + 24];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 3);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 48], c_CNS[(2 * i) + 48 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 24] = chainv[i];
		chainv[i] = state[i + 32];
	}

	TWEAK(chainv[4], chainv[5], chainv[6], chainv[7], 4);

#pragma unroll 8
	for (i = 0; i<8; i++) {
		STEP(c_CNS[(2 * i) + 64], c_CNS[(2 * i) + 64 + 1]);
	}

#pragma unroll 8
	for (i = 0; i<8; i++) {
		state[i + 32] = chainv[i];
	}
}
__device__ __forceinline__
void Update512(hashState *state, const uint32_t*data)
{
#pragma unroll 8
	for (int i = 0; i < 8; i++) state->buffer[i] = cuda_swab32(data[i]);
    rnd512_first(state->chainv, state->buffer);

#pragma unroll 8
	for (int i = 0; i < 8; i++) state->buffer[i] = cuda_swab32(data[i + 8]);
    rnd512(state);
}


/***************************************************/
__device__ __forceinline__
void finalization512(hashState *state, uint32_t *b)
{
    int i,j;

    state->buffer[0] = 0x80000000;
	#pragma unroll 7
    for(int i=1;i<8;i++) state->buffer[i] = 0;
	rnd512(state);

    /*---- blank round with m=0 ----*/
	rnd512_nullhash(state->chainv);

#pragma unroll 8
    for(i=0;i<8;i++) {
		b[i] = state->chainv[i + 8 * 0];
#pragma unroll 4
        for(j=1;j<5;j++) {
            b[i] ^= state->chainv[i+8*j];
        }
        b[i] = cuda_swab32((b[i]));
    }

	rnd512_nullhash(state->chainv);

#pragma unroll 8
    for(i=0;i<8;i++) {
		b[8 + i] = state->chainv[i + 8 * 0];
#pragma unroll 4
        for(j=1;j<5;j++) {
            b[8+i] ^= state->chainv[i+8*j];
        }
        b[8 + i] = cuda_swab32((b[8 + i]));
    }
}


typedef unsigned char BitSequence;

#define CUBEHASH_ROUNDS 16 /* this is r for CubeHashr/b */
#define CUBEHASH_BLOCKBYTES 32 /* this is b for CubeHashr/b */

#if __CUDA_ARCH__ < 350
#define LROT(x,bits) ((x << bits) | (x >> (32 - bits)))
#else
#define LROT(x, bits) __funnelshift_l(x, x, bits)
#endif

#define ROTATEUPWARDS7(a)  LROT(a,7)
#define ROTATEUPWARDS11(a) LROT(a,11)

#define SWAP(a,b) { uint32_t u = a; a = b; b = u; }

__device__ __constant__
static const uint32_t c_IV_512[32] = {

	0x2AEA2A61, 0x50F494D4, 0x2D538B8B,
	0x4167D83E, 0x3FEE2313, 0xC701CF8C,
	0xCC39968E, 0x50AC5695, 0x4D42C787,
	0xA647A8B3, 0x97CF0BEF, 0x825B4537,
	0xEEF864D2, 0xF22090C4, 0xD0E5CD33,
	0xA23911AE, 0xFCD398D9, 0x148FE485,
	0x1B017BEF, 0xB6444532, 0x6A536159,
	0x2FF5781C, 0x91FA7934, 0x0DBADEA9,
	0xD65C8A2B, 0xA5A70E75, 0xB1C62456,
	0xBC796576, 0x1921C8F7, 0xE7989AF1,
	0x7795D246, 0xD43E3B44
};

__device__ __forceinline__ void rrounds(uint32_t x[2][2][2][2][2])
{
	int r;
	int j;
	int k;
	int l;
	int m;

//	#pragma unroll 
	for (r = 0; r < CUBEHASH_ROUNDS; ++r) {

		/* "add x_0jklm into x_1jklmn modulo 2^32" */
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (l = 0; l < 2; ++l)
#pragma unroll 2
					for (m = 0; m < 2; ++m)
						x[1][j][k][l][m] += x[0][j][k][l][m];

		/* "rotate x_0jklm upwards by 7 bits" */
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (l = 0; l < 2; ++l)
#pragma unroll 2
					for (m = 0; m < 2; ++m)
						x[0][j][k][l][m] = ROTATEUPWARDS7(x[0][j][k][l][m]);

		/* "swap x_00klm with x_01klm" */
#pragma unroll 2
		for (k = 0; k < 2; ++k)
#pragma unroll 2
			for (l = 0; l < 2; ++l)
#pragma unroll 2
				for (m = 0; m < 2; ++m)
					SWAP(x[0][0][k][l][m], x[0][1][k][l][m])

					/* "xor x_1jklm into x_0jklm" */
#pragma unroll 2
					for (j = 0; j < 2; ++j)
#pragma unroll 2
						for (k = 0; k < 2; ++k)
#pragma unroll 2
							for (l = 0; l < 2; ++l)
#pragma unroll 2
								for (m = 0; m < 2; ++m)
									x[0][j][k][l][m] ^= x[1][j][k][l][m];

		/* "swap x_1jk0m with x_1jk1m" */
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (m = 0; m < 2; ++m)
					SWAP(x[1][j][k][0][m], x[1][j][k][1][m])

					/* "add x_0jklm into x_1jklm modulo 2^32" */
#pragma unroll 2
					for (j = 0; j < 2; ++j)
#pragma unroll 2
						for (k = 0; k < 2; ++k)
#pragma unroll 2
							for (l = 0; l < 2; ++l)
#pragma unroll 2
								for (m = 0; m < 2; ++m)
									x[1][j][k][l][m] += x[0][j][k][l][m];

		/* "rotate x_0jklm upwards by 11 bits" */
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (l = 0; l < 2; ++l)
#pragma unroll 2
					for (m = 0; m < 2; ++m)
						x[0][j][k][l][m] = ROTATEUPWARDS11(x[0][j][k][l][m]);

		/* "swap x_0j0lm with x_0j1lm" */
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (l = 0; l < 2; ++l)
#pragma unroll 2
				for (m = 0; m < 2; ++m)
					SWAP(x[0][j][0][l][m], x[0][j][1][l][m])

					/* "xor x_1jklm into x_0jklm" */
#pragma unroll 2
					for (j = 0; j < 2; ++j)
#pragma unroll 2
						for (k = 0; k < 2; ++k)
#pragma unroll 2
							for (l = 0; l < 2; ++l)
#pragma unroll 2
								for (m = 0; m < 2; ++m)
									x[0][j][k][l][m] ^= x[1][j][k][l][m];

		/* "swap x_1jkl0 with x_1jkl1" */
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (l = 0; l < 2; ++l)
					SWAP(x[1][j][k][l][0], x[1][j][k][l][1])

	}
}


__device__ __forceinline__ void block_tox(uint32_t *in, uint32_t x[2][2][2][2][2])
{
	int k;
	int l;
	int m;
//	uint32_t *in = block;

#pragma unroll 2
	for (k = 0; k < 2; ++k)
#pragma unroll 2
		for (l = 0; l < 2; ++l)
#pragma unroll 2
			for (m = 0; m < 2; ++m)
				x[0][0][k][l][m] ^= *in++;
}

__device__ __forceinline__ void hash_fromx(uint32_t *out, uint32_t x[2][2][2][2][2])
{
	int j;
	int k;
	int l;
	int m;
//	uint32_t *out = hash;

#pragma unroll 2
	for (j = 0; j < 2; ++j)
#pragma unroll 2
		for (k = 0; k < 2; ++k)
#pragma unroll 2
			for (l = 0; l < 2; ++l)
#pragma unroll 2
				for (m = 0; m < 2; ++m)
					*out++ = x[0][j][k][l][m];
}

void __device__ __forceinline__ Init(uint32_t x[2][2][2][2][2])
{
	int i, j, k, l, m;
#if 0
	/* "the first three state words x_00000, x_00001, x_00010" */
	/* "are set to the integers h/8, b, r respectively." */
	/* "the remaining state words are set to 0." */
#pragma unroll 2
	for (i = 0; i < 2; ++i)
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (l = 0; l < 2; ++l)
#pragma unroll 2
					for (m = 0; m < 2; ++m)
						x[i][j][k][l][m] = 0;
	x[0][0][0][0][0] = 512 / 8;
	x[0][0][0][0][1] = CUBEHASH_BLOCKBYTES;
	x[0][0][0][1][0] = CUBEHASH_ROUNDS;

	/* "the state is then transformed invertibly through 10r identical rounds */
	for (i = 0; i < 10; ++i) rrounds(x);
#else
	const uint32_t *iv = c_IV_512;

#pragma unroll 2
	for (i = 0; i < 2; ++i)
#pragma unroll 2
		for (j = 0; j < 2; ++j)
#pragma unroll 2
			for (k = 0; k < 2; ++k)
#pragma unroll 2
				for (l = 0; l < 2; ++l)
#pragma unroll 2
					for (m = 0; m < 2; ++m)
						x[i][j][k][l][m] = *iv++;
#endif
}

void __device__ __forceinline__ Update32(uint32_t x[2][2][2][2][2], const uint32_t *data)
{
	/* "xor the block into the first b bytes of the state" */
	/* "and then transform the state invertibly through r identical rounds" */
	block_tox((uint32_t*)data, x);
	rrounds(x);
}

void __device__ __forceinline__ Final(uint32_t x[2][2][2][2][2], uint32_t *hashval)
{
	int i;

	/* "the integer 1 is xored into the last state word x_11111" */
	x[1][1][1][1][1] ^= 1;

	/* "the state is then transformed invertibly through 10r identical rounds" */
//	#pragma unroll 10
	for (i = 0; i < 10; ++i) rrounds(x);

	/* "output the first h/8 bytes of the state" */
	hash_fromx(hashval, x);
}


/***************************************************/
// Die Hash-Funktion
__global__
void x11_luffaCubehash512_gpu_hash_64(uint32_t threads, uint32_t startNounce, uint64_t *g_hash, uint32_t *g_nonceVector)
{
    uint32_t thread = (blockDim.x * blockIdx.x + threadIdx.x);
    if (thread < threads)
    {
        uint32_t nounce = (g_nonceVector != NULL) ? g_nonceVector[thread] : (startNounce + thread);

        int hashPosition = nounce - startNounce;
        uint32_t *Hash = (uint32_t*)&g_hash[8 * hashPosition];

        hashState state;
#pragma unroll 40
        for(int i=0;i<40;i++) state.chainv[i] = c_IV[i];

		Update512(&state, Hash);
        finalization512(&state, Hash);
		//Cubehash

		uint32_t x[2][2][2][2][2];
		Init(x);
		// erste Hälfte des Hashes (32 bytes)
		Update32(x, Hash);
		// zweite Hälfte des Hashes (32 bytes)
		Update32(x, &Hash[8]);
		// Padding Block
		uint32_t last[8];
		last[0] = 0x80;
#pragma unroll 7
		for (int i = 1; i < 8; i++) last[i] = 0;
		Update32(x, last);
		Final(x, Hash);	
	}
}

__host__ void x11_luffaCubehash512_cpu_hash_64(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_nonceVector, uint32_t *d_hash, int order)
{
    const uint32_t threadsperblock = 256;

    // berechne wie viele Thread Blocks wir brauchen
    dim3 grid((threads + threadsperblock-1)/threadsperblock);
    dim3 block(threadsperblock);

	x11_luffaCubehash512_gpu_hash_64 << <grid, block>> >(threads, startNounce, (uint64_t*)d_hash, d_nonceVector);
}

