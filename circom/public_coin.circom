pragma circom 2.0.4;

include "./poseidon/poseidon.circom";
include "./utils.circom";

/**
 * Pseudo-random generator used to create and verify a STARK. Usually, random
 * coefficient are drawn during the proof when they are needed. This order is
 * recreated here, and as all of the inputs needed are available from the start,
 * we can create a component whose initialized at the start of the verification,
 * whose outputs will be accessed throughout the rest of the verification.
 * 
 * ARGUMENTS:
 * - See verify.circom
 * 
 * INPUTS:
 * - pub_coin_seed: serialized public inputs and context.
 * - trace_commitment: merkle root commit for the trace.
 * - constraint_commitment: merkle root commit for the constraints.
 * - ood_trace_frame: Out Of domain trace frame.
 * - ood_constraint_evaluations: Constraint polynomials evaluated out of domain
 * - pow_nonce: Proof of work nonce
 * 
 * OUTPUTS:
 * - transition_coeffs: coefficients for transition constraints needed for the OOD consistency check.
 * - boundary_coeffs: coefficients for boundary constraints needed for the OOD consistency check.
 * - deep_trace_coefficients: trace coefficients for DEEP composition polynomial.
 * - deep_constraint_coefficients: constraint coefficients for DEEP composition polynomial.
 * - degree_adjustment_coefficients : coefficients used when adjusting degrees during DEEP composition.
 * - layer_alphas: see fri.circom
 * - query_positions: positions at wich we will check the openings for both trace states and constraint evaluations.
 * - z: Out Of Domain point of evaluation, generated in the public coin.
 *
 * TODO: 
 * - The third value isnt used as long  as we do not have auxiliary trace segments.
     We could remove the hash and just increment our coin counter by one.
 */
template PublicCoin(
    ce_blowup_factor,
    lde_blowup_size,
    num_assertions,
    num_draws,
    num_fri_layers,
    num_pub_coin_seed,
    num_queries,
    num_transition_constraints,
    trace_length,
    trace_width
) {
    signal input pub_coin_seed[num_pub_coin_seed];
    signal input trace_commitment;
    signal input constraint_commitment;
    signal input ood_trace_frame[2][trace_width];
    signal input ood_constraint_evaluations[ce_blowup_factor];
    signal input pow_nonce;

    signal output transition_coeffs[num_transition_constraints][2];
    signal output boundary_coeffs[num_assertions][2];
    signal output deep_trace_coefficients[trace_width][3];
    signal output deep_constraint_coefficients[ce_blowup_factor];
    signal output degree_adjustment_coefficients[2];
    signal output layer_alphas[num_fri_layers];
    signal output query_positions[num_queries];
    signal output z;

    var num_seeds = 7;
    component reseed[num_seeds];

    var k = 0;

    // 0 - Initialize public coin seed with public inputs and context serialized
    reseed[k] = Poseidon(num_pub_coin_seed);
    for (var i = 0; i < num_pub_coin_seed; i++) {
        reseed[k].in[i] <== pub_coin_seed[i];
    }

    // 1 - Reseeding with trace commitment

    k += 1;
    reseed[k] = Poseidon(2);
    reseed[k].in[0] <== reseed[k-1].out;
    reseed[k].in[1] <== trace_commitment;

    // drawing transition and constraint coefficients for OOD consistency check
    component trace_coin[num_transition_constraints + num_assertions][2] = Poseidon(2);
    for (var i = 0; i < num_transition_constraints; i++) {
        for (var j = 0; j < 2; j++){
            trace_coin[i][j].in[0] <== reseed[k].out;
            trace_coin[i][j].in[1] <== 2 * i + j + 1;
            transition_coeffs[i][j] <== trace_coin[i][j].out;
        }
    }

    for (var i = 0; i < num_assertions; i++) {
        for (var j = 0; j < 2; j++){
            trace_coin[i + num_transition_constraints][j].in[0] <== reseed[k].out;
            trace_coin[i + num_transition_constraints][j].in[1] <== 2 * (i + num_transition_constraints) + j + 1;
            boundary_coeffs[i] <== trace_coin[i + num_transition_constraints][j].out;
        }
    }


    // 2 - Reseeding with constraint commitment

    k += 1;
    reseed[k] = Poseidon(2);
    reseed[k].in[0] <== reseed[k-1].out;
    reseed[k].in[1] <== constraint_commitment;

    // OOD point for evaluations
    component constraint_coin = Poseidon(2);
    constraint_coin.in[0] <== reseed[k].out;
    constraint_coin.in[1] <== 1;
    z <== constraint_coin.out;


    // 3 - Reseeding with ood_trace_frame

    k += 1;
    reseed[k] = Poseidon(1 + trace_width);
    reseed[k].in[0] <== reseed[k-1].out;
    for (var i = 0; i < trace_width; i++){
        reseed[k].in[i + 1] <== ood_trace_frame[0][i];
    }

    k += 1;
    reseed[k] = Poseidon(1 + trace_width);
    reseed[k].in[0] <== reseed[k-1].out;
    for (var i = 0; i < trace_width; i++){
        reseed[k].in[i + 1] <== ood_trace_frame[1][i];
    }

    // drawing all coefficient needed for the DEEP composition polynomial
    component deep_coin[3 * trace_width + ce_blowup_factor + 2] = Poseidon(2);
    for (var i = 0; i < trace_width; i++){
        for (var j = 0; j < 3; j++){
        deep_coin[3 * i + j].in[0] <== reseed[k].out;
        deep_coin[3 * i + j].in[1] <== 3 * i + j + 1;
        deep_trace_coefficients[i][j] <== deep_coin[3 * i + j].out;
        }
    }

    for (var i = 0; i < trace_width; i++){
        deep_coin[i + 3 * trace_width].in[0] <== reseed[k].out;
        deep_coin[i + 3 * trace_width].in[1] <== i + 1;
        deep_constraint_coefficients[i] <== deep_coin[i + 3 * trace_width].out ;
    }

    for (var i = 0; i < 2; i++){
        deep_coin[i + 3 * trace_width + ce_blowup_factor].in[0] <== reseed[k].out;
        deep_coin[i + 3 * trace_width + ce_blowup_factor].in[1] <== i + 1;
        degree_adjustment_coefficients[i] <== deep_coin[i + 3 * trace_width + ce_blowup_factor].out ;
    }


    // 4 - Reseeding with OOD constraint evaluations

    k += 1;
    reseed[k] = Poseidon(1 + ce_blowup_factor);
    reseed[k].in[0] <== reseed[k-1].out;
    for (var i = 0; i < ce_blowup_factor; i++) {
        reseed[k].in[i+1] <== ood_constraint_evaluations[i];
    }

    // drawing alphas for fri verification
    component fri_coin[num_fri_layers] = Poseidon(2);
    for (var i = 0; i < num_fri_layers; i++) {
        fri_coin.in[0] <== reseed[k].out;
        fri_coin.in[1] <== i + 1;
        layer_alphas[i] <== fri_coin[i].out;
    }


    // 5 - Reseeding with proof of work

    k += 1;
    reseed[k] = Poseidon(2);
    reseed[k].in[0] <== reseed[k-1].out;
    reseed[k].in[1] <== pow_nonce;

    // TODO: check proof of work


    // drawing querypositions
    // could be optimized to divide the number of hashes by 4, but we would also
    // need to implement the same optimization in Winterfell.
    component query_coin[num_draws];
    component remove_duplicates = RemoveDuplicates(num_draws,num_queries)
    signal query_draws[num_draws];
    for (var i = 0; i < num_draws) {
        query_coin[i] <== reseed[k].out;
        query_coin[i] <== i + 1;
        remove_duplicates.in[i] <== query_coin[i].out;
    }

    // compute the size of the query elements in bits
    var bit_mask = trace_length * lde_blowup_size;
    var mask_size = 0;
    while(bit_mask != 0) {
        bit_mask \= 2;
        mask_size += 1;
    }

    component num2bits[num_queries];
    component bits2num[num_queries];
    for (var i = 0; i < num_queries; i++){
        num2bits[i] = Num2Bits(mask_size);
        num2bits[i].in <== remove_duplicates.out[i];
        bits2num[i] = Bits2Num(mask_size);
        for (var j = 0; j < mask_size; j++){
            bits2num[i].in[j] = num2bits[i].out[j]
        }
        query_positions[i] <== bits2num[i].out;
    }
}