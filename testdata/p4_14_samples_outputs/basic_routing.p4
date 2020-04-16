#include <core.p4>
#define V1MODEL_VERSION 20200408
#include <v1model.p4>

struct ingress_metadata_t {
    bit<12> vrf;
    bit<16> bd;
    bit<16> nexthop_index;
}

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

struct metadata {
    @name(".ingress_metadata") 
    ingress_metadata_t ingress_metadata;
}

struct headers {
    @name(".ethernet") 
    ethernet_t ethernet;
    @name(".ipv4") 
    ipv4_t     ipv4;
}

parser ParserImpl(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name(".parse_ethernet") state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            16w0x800: parse_ipv4;
            default: accept;
        }
    }
    @name(".parse_ipv4") state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
    @name(".start") state start {
        transition parse_ethernet;
    }
}

control egress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name(".on_miss") action on_miss() {
    }
    @name(".rewrite_src_dst_mac") action rewrite_src_dst_mac(bit<48> smac, bit<48> dmac) {
        hdr.ethernet.srcAddr = smac;
        hdr.ethernet.dstAddr = dmac;
    }
    @name(".rewrite_mac") table rewrite_mac {
        actions = {
            on_miss;
            rewrite_src_dst_mac;
        }
        key = {
            meta.ingress_metadata.nexthop_index: exact;
        }
        size = 32768;
    }
    apply {
        rewrite_mac.apply();
    }
}

control ingress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name(".set_vrf") action set_vrf(bit<12> vrf) {
        meta.ingress_metadata.vrf = vrf;
    }
    @name(".on_miss") action on_miss() {
    }
    @name(".fib_hit_nexthop") action fib_hit_nexthop(bit<16> nexthop_index) {
        meta.ingress_metadata.nexthop_index = nexthop_index;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 8w1;
    }
    @name(".set_egress_details") action set_egress_details(bit<9> egress_spec) {
        standard_metadata.egress_spec = egress_spec;
    }
    @name(".set_bd") action set_bd(bit<16> bd) {
        meta.ingress_metadata.bd = bd;
    }
    @name(".bd") table bd {
        actions = {
            set_vrf;
        }
        key = {
            meta.ingress_metadata.bd: exact;
        }
        size = 65536;
    }
    @name(".ipv4_fib") table ipv4_fib {
        actions = {
            on_miss;
            fib_hit_nexthop;
        }
        key = {
            meta.ingress_metadata.vrf: exact;
            hdr.ipv4.dstAddr         : exact;
        }
        size = 131072;
    }
    @name(".ipv4_fib_lpm") table ipv4_fib_lpm {
        actions = {
            on_miss;
            fib_hit_nexthop;
        }
        key = {
            meta.ingress_metadata.vrf: exact;
            hdr.ipv4.dstAddr         : lpm;
        }
        size = 16384;
    }
    @name(".nexthop") table nexthop {
        actions = {
            on_miss;
            set_egress_details;
        }
        key = {
            meta.ingress_metadata.nexthop_index: exact;
        }
        size = 32768;
    }
    @name(".port_mapping") table port_mapping {
        actions = {
            set_bd;
        }
        key = {
            standard_metadata.ingress_port: exact;
        }
        size = 32768;
    }
    apply {
        if (hdr.ipv4.isValid()) {
            port_mapping.apply();
            bd.apply();
            switch (ipv4_fib.apply().action_run) {
                on_miss: {
                    ipv4_fib_lpm.apply();
                }
            }

            nexthop.apply();
        }
    }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
        verify_checksum(true, { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv, hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr }, hdr.ipv4.hdrChecksum, HashAlgorithm.csum16);
    }
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply {
        update_checksum(true, { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv, hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr }, hdr.ipv4.hdrChecksum, HashAlgorithm.csum16);
    }
}

V1Switch(ParserImpl(), verifyChecksum(), ingress(), egress(), computeChecksum(), DeparserImpl()) main;

