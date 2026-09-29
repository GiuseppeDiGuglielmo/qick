// ctypes wrapper around the HLS NN() core: 800 integer inputs in hardware
// order (in_local[2n] = I, in_local[2n+1] = Q) -> the integer logit
#include "NN.h"
extern "C" double nn_eval(const int *x) {
    input_t in[N_INPUT_1_1];
    result_t out[N_LAYER_5];
    for (int i = 0; i < N_INPUT_1_1; i++) in[i] = x[i];
    NN(in, out);
    return out[0].to_double();
}
