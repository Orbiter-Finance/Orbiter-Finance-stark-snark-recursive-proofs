pragma circom 2.0.4;

include "../circom/utils.circom"

template BasicTransitions(trace_width){
    signal input frame[2][2] ;
    signal output out[trace_width];
    signal output transition_degree[trace_length];

    // frame[0] = current | frame[1] = next

    // transition 0
    out[0] <== frame[1][0] - (frame[0][0] + 1)
    transition_degree[0] <== 1;
    
    // transition 1
    out[1] <== frame[1][1] - (frame[0][1] + frame[0][0] + 1)
    transition_degree[1] <== 1;
}

template BasicAssertions(num_assertions, trace_length, trace_width, trace_generator){

    signal input result;
    signal input frame[2][trace_width] ;
    signal output out[num_assertions];
    signal output divisor_degree[num_assertions];
    signal numerator[num_assertions];

    // single assertions
    signal value[num_assertions];
    signal step[num_assertions];
    signal register[num_assertions];

    /* HERE DEFINE YOUR ASSERTIONS */

    value[0] = 1;
    step[0] = 0;
    register[0] = 0;

    value[1] = 1;
    step[1] = 0;
    register[0] = 1;

    value[2] = result;
    step[2] = trace_length;
    register[0] = 1;


    // boundary constraints evaluation
    component pow[num_assertions];
    for (int i = 0; i < num_assertions; i++) {
        numerator[i] <== frame[0][register[i]] - value[i];
        pow[i] = Pow(step[i]);
        pow[i].in <== trace_generator;
        out[i] <== numerator[i] / (x - pow[i].out)
        divisor_degree[i] = step[i];

    }

    
}


