#include <core.p4>
#include <psa.p4>

struct EMPTY {
}

typedef bit<48> EthernetAddress;
struct user_meta_t {
    bit<16> data;
}

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

parser MyIP(packet_in buffer, out ethernet_t eth, inout user_meta_t b, in psa_ingress_parser_input_metadata_t c, in EMPTY d, in EMPTY e) {
    state start {
        buffer.extract<ethernet_t>(eth);
        transition accept;
    }
}

parser MyEP(packet_in buffer, out EMPTY a, inout EMPTY b, in psa_egress_parser_input_metadata_t c, in EMPTY d, in EMPTY e, in EMPTY f) {
    state start {
        transition accept;
    }
}

control MyIC(inout ethernet_t a, inout user_meta_t b, in psa_ingress_input_metadata_t c, inout psa_ingress_output_metadata_t d) {
    @name(".NoAction") action NoAction_0() {
    }
    @name("MyIC.h") Hash<bit<16>>(PSA_HashAlgorithm_t.CRC16) h_0;
    @name("MyIC.a1") action a1() {
        b.data = h_0.get_hash<ethernet_t>(a);
    }
    @name("MyIC.tbl") table tbl_0 {
        key = {
            a.srcAddr: exact @name("a.srcAddr") ;
        }
        actions = {
            NoAction_0();
            a1();
        }
        default_action = NoAction_0();
    }
    apply {
        tbl_0.apply();
    }
}

control MyEC(inout EMPTY a, inout EMPTY b, in psa_egress_input_metadata_t c, inout psa_egress_output_metadata_t d) {
    apply {
    }
}

control MyID(packet_out buffer, out EMPTY a, out EMPTY b, out EMPTY c, inout ethernet_t d, in user_meta_t e, in psa_ingress_output_metadata_t f) {
    apply {
    }
}

control MyED(packet_out buffer, out EMPTY a, out EMPTY b, inout EMPTY c, in EMPTY d, in psa_egress_output_metadata_t e, in psa_egress_deparser_input_metadata_t f) {
    apply {
    }
}

IngressPipeline<ethernet_t, user_meta_t, EMPTY, EMPTY, EMPTY, EMPTY>(MyIP(), MyIC(), MyID()) ip;

EgressPipeline<EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY>(MyEP(), MyEC(), MyED()) ep;

PSA_Switch<ethernet_t, user_meta_t, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY>(ip, PacketReplicationEngine(), ep, BufferingQueueingEngine()) main;

