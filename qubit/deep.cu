/*
 * deepcoin algorithm
 *
 */
extern "C" {
#include "sph/sph_luffa.h"
#include "sph/sph_cubehash.h"
#include "sph/sph_shavite.h"
#include "sph/sph_simd.h"
#include "sph/sph_echo.h"
}

#include "miner.h"

#include "cuda_helper.h"

static uint32_t *d_hash[MAX_GPUS];

extern void qubit_luffa512_cpu_init(int thr_id, uint32_t threads);
extern void qubit_luffa512_cpu_setBlock_80(void *pdata);
extern void qubit_luffa512_cpu_hash_80(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_hash, int order);
extern void qubit_luffa512_cpufinal_setBlock_80(void *pdata, const void *ptarget);
extern uint32_t qubit_luffa512_cpu_finalhash_80(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_hash, int order);

extern void x11_cubehash512_cpu_hash_64(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_nonceVector, uint32_t *d_hash, int order);

extern void x11_echo512_cpu_init(int thr_id, uint32_t threads);
extern void x11_echo512_cpu_hash_64(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *d_nonceVector, uint32_t *d_hash, int order);

extern "C" void deephash(void *state, const void *input)
{
	// luffa1-cubehash2-shavite3-simd4-echo5
	sph_luffa512_context ctx_luffa;
	sph_cubehash512_context ctx_cubehash;
	sph_echo512_context ctx_echo;

	uint8_t hash[64];

	sph_luffa512_init(&ctx_luffa);
	sph_luffa512 (&ctx_luffa, input, 80);
	sph_luffa512_close(&ctx_luffa, (void*) hash);

	sph_cubehash512_init(&ctx_cubehash);
	sph_cubehash512 (&ctx_cubehash, (const void*) hash, 64);
	sph_cubehash512_close(&ctx_cubehash, (void*) hash);

	sph_echo512_init(&ctx_echo);
	sph_echo512 (&ctx_echo, (const void*) hash, 64);
	sph_echo512_close(&ctx_echo, (void*) hash);

	memcpy(state, hash, 32);
}

static bool init[MAX_GPUS] = { 0 };

extern "C" int scanhash_deep(int thr_id, uint32_t *pdata,
	const uint32_t *ptarget, uint32_t max_nonce,
	unsigned long *hashes_done)
{
	const uint32_t first_nonce = pdata[19];
	uint32_t endiandata[20];
	uint32_t throughput = device_intensity(thr_id, __func__, 1U << 19); // 256*256*8
	throughput = min(throughput, (max_nonce - first_nonce));

	if (opt_benchmark)
		((uint32_t*)ptarget)[7] = 0x0000f;

	if (!init[thr_id])
	{
		cudaSetDevice(device_map[thr_id]);
		cudaDeviceReset();
		cudaSetDeviceFlags(cudaDeviceScheduleBlockingSync);
		cudaDeviceSetCacheConfig(cudaFuncCachePreferL1);

		cudaMalloc(&d_hash[thr_id], 16 * sizeof(uint32_t) * throughput);

		qubit_luffa512_cpu_init(thr_id, throughput);
		x11_echo512_cpu_init(thr_id, throughput);

		cuda_check_cpu_init(thr_id, throughput);

		init[thr_id] = true;
	}

	for (int k=0; k < 20; k++)
		be32enc(&endiandata[k], ((uint32_t*)pdata)[k]);

	qubit_luffa512_cpufinal_setBlock_80((void*)endiandata,ptarget);
	cuda_check_cpu_setTarget(ptarget);

	do {
		int order = 0;

		qubit_luffa512_cpu_hash_80(thr_id, throughput, pdata[19], d_hash[thr_id], order++);
		x11_cubehash512_cpu_hash_64(thr_id, throughput, pdata[19], NULL, d_hash[thr_id], order++);
		x11_echo512_cpu_hash_64(thr_id, throughput, pdata[19], NULL, d_hash[thr_id], order++);

		uint32_t foundNonce = cuda_check_hash(thr_id, throughput, pdata[19], d_hash[thr_id]);
		if (foundNonce != UINT32_MAX)
		{
			const uint32_t Htarg = ptarget[7];
			uint32_t vhash64[8];
			be32enc(&endiandata[19], foundNonce);
			deephash(vhash64, endiandata);

			if (vhash64[7] <= Htarg && fulltest(vhash64, ptarget)) {
				int res = 1;
				uint32_t secNonce = cuda_check_hash_suppl(thr_id, throughput, pdata[19], d_hash[thr_id], foundNonce);
				*hashes_done = pdata[19] - first_nonce + throughput;
				if (secNonce != 0) {
					pdata[21] = secNonce;
					res++;
				}
				pdata[19] = foundNonce;
				return res;
			}
			else {
				applog(LOG_INFO, "GPU #%d: result for nonce $%08X does not validate on CPU!", thr_id, foundNonce);
			}
		}

		pdata[19] += throughput;
	} while (!work_restart[thr_id].restart && ((uint64_t)max_nonce > ((uint64_t)(pdata[19]) + (uint64_t)throughput)));

	*hashes_done = pdata[19] - first_nonce + 1;
	return 0;
}
