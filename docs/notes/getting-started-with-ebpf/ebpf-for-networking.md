**XDP**: eXpress Data Path
Type of event that we can attach eBPF to - for incoming network packets
The first possible opportunity for looking into a network packet as it arrives into a machine across a network interface

![XDP](/docs/images/getting-started-with-ebpf/ebpf-for-networking/xdp.png)

Example: using XDP to drop *ping* packets

-  Loading our *xdp* function into *BPF.XDP*

![XDP Code (1)](/docs/images/getting-started-with-ebpf/ebpf-for-networking/xdp-code1.png)

- XDP's context is the network packet, and it's defined by a structure called *xdp_md*
- If we change the first *XDP_PASS* to *XDP_DROP*, pings get dropped

![XDP Code (2)](/docs/images/getting-started-with-ebpf/ebpf-for-networking/xdp-code2.png)

Some NICs support XDP Offload: eBPF program runs on the NIC itself
Packets can be modified, dropped, or forwarded without using CPU cycles

![XDP Offload](/docs/images/getting-started-with-ebpf/ebpf-for-networking/xdp-nic.png)

We can attach eBPF events in several stages of the Network Stack:

![eBPF in the Networking Stack](/docs/images/getting-started-with-ebpf/ebpf-for-networking/ebpf-network-layers.png)

**Traffic Control (TC):** subsystem in the kernel that regulates how traffic is scheduled using classifiers
eBPF programs can be attached in TC as custom classifiers, and can also manipulate, drop, or redirect packets here too

**Cilium:** in containerized environments, IPs are reused for different applications as demand varies. Cilium is aware of Kubernetes identities.

**Container Networking w/out eBPF:**

![Container Networking](/docs/images/getting-started-with-ebpf/ebpf-for-networking/container-networking.png)

**Container Networking w/ eBPF:** using eBPF (as we do in Cilium), we can bypass a lot of the networking stack on the host and send packets directly to the pod, which is much more efficient.

![Container Networking with Cilium](/docs/images/getting-started-with-ebpf/ebpf-for-networking/cilium-container-networking.png)

**Cilium Network Policy:** eBPF programs drop packets